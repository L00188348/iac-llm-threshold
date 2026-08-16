terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
  default     = "multi-tier-app"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "az_count" {
  type        = number
  description = "Number of AZs to use"
  default     = 2
}

variable "alb_ingress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = optional(string)
  }))
  description = "Ingress rules for the ALB security group"
  default = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP from anywhere"
    }
  ]
}

variable "ecs_ingress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    source_sg_index = optional(number)
    cidr_blocks     = optional(list(string))
    description     = optional(string)
  }))
  description = "Ingress rules for the ECS security group; if source_sg_index is set, rule references another security group"
  default = [
    {
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      source_sg_index = 0
      description     = "HTTP from ALB SG"
    }
  ]
}

variable "ecs_container_image" {
  type        = string
  description = "Container image for the ECS service"
  default     = "public.ecr.aws/docker/library/nginx:latest"
}

variable "ecs_container_port" {
  type        = number
  description = "Container port exposed by the application"
  default     = 80
}

variable "ecs_cpu" {
  type        = number
  description = "Fargate task CPU units"
  default     = 256
}

variable "ecs_memory" {
  type        = number
  description = "Fargate task memory"
  default     = 512
}

variable "ecs_desired_count" {
  type        = number
  description = "Desired number of ECS tasks"
  default     = 2
}

variable "ecs_task_role_policy_arns" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the ECS task role"
  default     = []
}

variable "dynamodb_table_name" {
  type        = string
  description = "DynamoDB table name"
  default     = "app-backend"
}

variable "dynamodb_hash_key" {
  type        = string
  description = "DynamoDB hash key name"
  default     = "pk"
}

variable "dynamodb_billing_mode" {
  type        = string
  description = "DynamoDB billing mode"
  default     = "PAY_PER_REQUEST"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default = {
    ManagedBy = "Terraform"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  common_tags  = merge(var.tags, { Project = var.project_name })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index % length(local.selected_azs)]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.selected_azs[count.index % length(local.selected_azs)]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.alb_ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = try(ingress.value.description, null)
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb-sg"
  })
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.ecs_ingress_rules
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      security_groups = try(ingress.value.source_sg_index, null) != null ? [aws_security_group.alb.id] : null
      cidr_blocks     = try(ingress.value.cidr_blocks, null)
      description     = try(ingress.value.description, null)
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-sg"
  })
}

resource "aws_lb" "this" {
  name               = substr("${var.project_name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb"
  })
}

resource "aws_lb_target_group" "this" {
  name        = substr("${var.project_name}-tg", 0, 32)
  port        = var.ecs_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             =