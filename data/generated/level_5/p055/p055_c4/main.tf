variable "aws_region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix for all resources."
  default     = "ecs-sidecar-app"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "environment_variables" {
  type = object({
    main    = map(string)
    sidecar = map(string)
  })
  description = "Environment variables for main and sidecar containers."
  default = {
    main = {
      APP_ENV   = "production"
      APP_COLOR = "blue"
    }
    sidecar = {
      SIDECAR_MODE = "proxy"
      LOG_LEVEL    = "info"
    }
  }
}

variable "main_container_image" {
  type        = string
  description = "Docker image for the main container."
  default     = "nginx:1.27"
}

variable "sidecar_container_image" {
  type        = string
  description = "Docker image for the sidecar container."
  default     = "public.ecr.aws/docker/library/busybox:latest"
}

variable "main_container_port" {
  type        = number
  description = "Port exposed by the main container."
  default     = 80
}

variable "desired_count" {
  type        = number
  description = "Desired number of ECS tasks."
  default     = 2
}

variable "cpu" {
  type        = number
  description = "CPU units for the task."
  default     = 256
}

variable "memory" {
  type        = number
  description = "Memory for the task in MiB."
  default     = 512
}

variable "aws_profile" {
  type        = string
  description = "AWS profile name, if needed."
  default     = null
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.project_name
  azs  = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  main_container_environment = [
    for k, v in var.environment_variables.main : {
      name  = k
      value = v
    }
  ]

  sidecar_container_environment = [
    for k, v in var.environment_variables.sidecar : {
      name  = k
      value = v
    }
  ]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(range(length(var.public_subnet_cidrs)))

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[each.value]
  availability_zone       = local.azs[each.value]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${each.value + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs-sg"
  description = "ECS tasks security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = var.main_container_port
    to_port         = var.main_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-ecs-sg"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.name}"
  retention_in_days  = 7
  skip_destroy       = false
}

resource "aws_lb" "this" {
  name               = substr(replace("${local.name}-alb", "/[^a-zA-Z0-9-]/", "-"), 0, 32)
  load_balancer_type  = "application"
  security_groups     = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  internal            = false

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_lb_target_group" "this" {
  name        = substr(replace("${local.name}-tg", "/[^a-zA-Z0-9-]/", "-"), 0, 32)
  port        = var.main_container_port
  protocol    = "HTTP"
  target_type  = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    path                = "/"
    matcher             = "200-399"
    timeout             = 5
  }

  tags = {
    Name = "${local.name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${local.name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn             = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "main"
      image     = var.main_container_image
      essential = true
      portMappings = [
        {
          containerPort = var.main_container_port
          hostPort      = var.main_container_port
          protocol      = "tcp"
        }
      ]
      environment = local.main_container_environment
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "main"
        }
      }
    },
    {
      name      = "sidecar"
      image     = var.sidecar_container_image
      essential = true
      environment = local.sidecar_container_environment
      command = ["sh", "-c", "while true; do echo sidecar running; sleep 30; done"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "sidecar"
        }
      }
    }
  ])
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action =