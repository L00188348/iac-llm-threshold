terraform {
  required_version = ">= 1.3.0"

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

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability Zones to use"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for EC2 instances"
  default     = ""
}

variable "asg_min_size" {
  type        = number
  description = "Minimum ASG size"
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "Maximum ASG size"
  default     = 3
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired ASG capacity"
  default     = 2
}

variable "cpu_threshold_percent" {
  type        = number
  description = "CPU utilization threshold percentage for scaling"
  default     = 70
}

variable "scale_out_adjustment" {
  type        = number
  description = "Number of instances to add when scaling out"
  default     = 1
}

variable "scale_out_cooldown" {
  type        = number
  description = "Cooldown period for scaling out"
  default     = 300
}

variable "scale_in_cooldown" {
  type        = number
  description = "Cooldown period for scaling in"
  default     = 300
}

data "aws_ami" "amazon_linux" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  effective_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux[0].id
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "app-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "app-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index % length(var.availability_zones)]
  map_public_ip_on_launch = true

  tags = {
    Name = "app-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "app-public-rt"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "app-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

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
    Name = "app-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "app-instance-sg"
  description = "Security group for application instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "app-instance-sg"
  }
}

resource "aws_lb" "app" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "app-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type  = "instance"
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200-399"
    protocol            = "HTTP"
  }

  tags = {
    Name = "app-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-lt-"
  image_id      = local.effective_ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -euxo pipefail
              dnf update -y
              dnf install -y nginx
              cat > /usr/share/nginx/html/index.html <<'HTML'
              <html>
              <head><title>App Bootstrap</title></head>
              <body><h1>Application is running</h1></body>
              </html>
              HTML
              systemctl enable nginx
              systemctl restart nginx
              EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "app-instance"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "app-volume"
    }
  }

  tags = {
    Name = "app-lt"
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.public[*].id
  health_check_type   = "ELB"
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "app-asg-instance"
    propagate_at_launch = true
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "app-scale-out"
  autoscaling_group_name  = aws_autoscaling_group.app.name
  policy_type            = "SimpleScaling"
  adjustment_type        =