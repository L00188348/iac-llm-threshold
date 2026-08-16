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
  type    = string
  default = "us-east-1"
}

variable "asg_config" {
  type = object({
    name               = string
    min_size           = number
    max_size           = number
    desired_capacity   = number
    instance_type      = string
    target_group_arn   = string
  })

  default = {
    name             = "test-asg"
    min_size         = 1
    max_size         = 3
    desired_capacity  = 2
    instance_type    = "t3.micro"
    target_group_arn = ""
  }

  validation {
    condition     = var.asg_config.min_size <= var.asg_config.desired_capacity && var.asg_config.desired_capacity <= var.asg_config.max_size
    error_message = "asg_config must satisfy min_size <= desired_capacity <= max_size."
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "asg" {
  name_prefix = "${var.asg_config.name}-asg-"
  description = "Security group for ASG instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.asg_config.name}-alb-"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.default.id

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
}

resource "aws_lb" "this" {
  name               = substr(replace(var.asg_config.name, "_", "-"), 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "this" {
  name        = substr(replace("${var.asg_config.name}-tg", "_", "-"), 0, 32)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path = "/"
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

locals {
  effective_target_group_arn = var.asg_config.target_group_arn != "" ? var.asg_config.target_group_arn : aws_lb_target_group.this.arn
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.asg_config.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.asg_config.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.asg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              python3 -m http.server 80 &
              EOF
  )
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_autoscaling_group" "this" {
  name                = var.asg_config.name
  min_size            = var.asg_config.min_size
  max_size            = var.asg_config.max_size
  desired_capacity    = var.asg_config.desired_capacity
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  target_group_arns = [local.effective_target_group_arn]

  tag {
    key                 = "Name"
    value               = var.asg_config.name
    propagate_at_launch = true
  }
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}