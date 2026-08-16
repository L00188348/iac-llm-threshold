terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to use"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "ami_owner" {
  type        = string
  description = "AMI owner ID"
  default     = "amazon"
}

variable "ami_name_filter" {
  type        = string
  description = "AMI name filter"
  default     = "amzn2-ami-hvm-*-x86_64-gp2"
}

variable "asg_min_size" {
  type        = number
  description = "ASG minimum size"
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "ASG maximum size"
  default     = 3
}

variable "asg_desired_capacity" {
  type        = number
  description = "ASG desired capacity"
  default     = 1
}

variable "cpu_threshold" {
  type        = number
  description = "CPU utilization threshold for scaling"
  default     = 70
}

variable "scaling_adjustment" {
  type        = number
  description = "Number of instances to add when scaling out"
  default     = 1
}

variable "evaluation_periods" {
  type        = number
  description = "Number of periods to evaluate for the alarm"
  default     = 2
}

variable "metric_period" {
  type        = number
  description = "CloudWatch metric period in seconds"
  default     = 60
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  bootstrap_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    yum update -y
    yum install -y httpd

    cat <<'HTML' >/var/www/html/index.html
    <html>
      <head><title>Bootstrapped App</title></head>
      <body>
        <h1>Application is running</h1>
      </body>
    </html>
    HTML

    systemctl enable httpd
    systemctl start httpd
  EOF
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index % length(var.availability_zones)]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

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
    Name = "alb-sg"
  }
}

resource "aws_security_group" "asg" {
  name        = "asg-sg"
  description = "Security group for ASG instances"
  vpc_id      = aws_vpc.main.id

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

  tags = {
    Name = "asg-sg"
  }
}

resource "aws_lb" "app" {
  name               = "app-alb"
  load_balancer_type  = "application"
  internal           = false
  security_groups     = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "app-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
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
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.asg.id]

  user_data = base64encode(local.bootstrap_user_data)

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
}

resource "aws_autoscaling_group" "app" {
  name                      = "app-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.public[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.app.arn]
  force_delete              = true

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
  name                   = "scale-out-policy"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = var.scaling_adjustment
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-utilization"
  alarm_description   = "Scale out when average CPU utilization exceeds threshold"
  comparison_operator = "GreaterThanThreshold