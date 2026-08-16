variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "name" {
  type        = string
  default     = "ecs-sidecar-app"
  description = "Base name for resources"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "container_image" {
  type        = string
  default     = "nginx:1.27"
  description = "Main application container image"
}

variable "sidecar_image" {
  type        = string
  default     = "amazon/aws-for-fluent-bit:latest"
  description = "Sidecar container image"
}

variable "main_container_port" {
  type        = number
  default     = 80
  description = "Main container port"
}

variable "sidecar_container_port" {
  type        = number
  default     = 24224
  description = "Sidecar container port"
}

variable "desired_count" {
  type        = number
  default     = 1
  description = "Desired number of ECS tasks"
}

variable "cpu" {
  type        = number
  default     = 256
  description = "Task CPU units"
}

variable "memory" {
  type        = number
  default     = 512
  description = "Task memory in MiB"
}

variable "environment_variables" {
  type = object({
    main    = map(string)
    sidecar = map(string)
  })
  default = {
    main = {
      APP_ENV     = "production"
      APP_MESSAGE  = "Hello from ECS"
      LOG_LEVEL    = "info"
    }
    sidecar = {
      FLUENT_BIT_LOG_LEVEL = "info"
      ENABLE_METRICS       = "true"
    }
  }
  description = "Environment variables for main and sidecar containers"
}

variable "container_healthcheck_path" {
  type        = string
  default     = "/"
  description = "Health check path for the ALB target group"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs-sg"
  description = "ECS tasks security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Traffic from ALB"
    from_port       = var.main_container_port
    to_port         = var.main_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Sidecar port within VPC"
    from_port   = var.sidecar_container_port
    to_port     = var.sidecar_container_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ecs-sg"
  }
}

resource "aws_cloudwatch_log_group" "containers" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7

  tags = {
    Name = "${var.name}-logs"
  }
}

resource "aws_lb" "this" {
  name               = replace(substr("${var.name}-alb", 0, 32), "/[^a-zA-Z0-9-]/", "-")
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_lb_target_group" "this" {
  name        = replace(substr("${var.name}-tg", 0, 32), "/[^a-zA-Z0-9-]/", "-")
  port        = var.main_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    path                = var.container_healthcheck_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name}-tg"
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
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_iam_role" "task_execution" {
  name = "${var.name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${var.name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "main"
      image     = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = var.main_container_port
          hostPort      =