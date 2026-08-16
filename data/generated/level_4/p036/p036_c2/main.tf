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

variable "alb_config" {
  type = object({
    name              = string
    vpc_id            = string
    subnet_ids        = list(string)
    health_check_path = string
  })
  default = {
    name              = "test-alb"
    vpc_id            = ""
    subnet_ids        = []
    health_check_path = "/health"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  use_existing_network = var.alb_config.vpc_id != "" && length(var.alb_config.subnet_ids) >= 2
  vpc_id               = local.use_existing_network ? var.alb_config.vpc_id : aws_vpc.this[0].id
  subnet_ids           = local.use_existing_network ? var.alb_config.subnet_ids : aws_subnet.this[*].id
}

resource "aws_vpc" "this" {
  count                = local.use_existing_network ? 0 : 1
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.alb_config.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  count  = local.use_existing_network ? 0 : 1
  vpc_id = aws_vpc.this[0].id

  tags = {
    Name = "${var.alb_config.name}-igw"
  }
}

resource "aws_route_table" "this" {
  count  = local.use_existing_network ? 0 : 1
  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = {
    Name = "${var.alb_config.name}-rt"
  }
}

resource "aws_subnet" "this" {
  count                   = local.use_existing_network ? 0 : 2
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = cidrsubnet(aws_vpc.this[0].cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch  = true

  tags = {
    Name = "${var.alb_config.name}-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "this" {
  count          = local.use_existing_network ? 0 : 2
  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = aws_route_table.this[0].id
}

resource "aws_security_group" "alb" {
  name        = "${var.alb_config.name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = local.vpc_id

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
    Name = "${var.alb_config.name}-alb-sg"
  }
}

resource "aws_security_group" "asg" {
  name        = "${var.alb_config.name}-asg-sg"
  description = "Security group for ASG instances"
  vpc_id      = local.vpc_id

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
    Name = "${var.alb_config.name}-asg-sg"
  }
}

resource "aws_lb" "this" {
  name               = var.alb_config.name
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  tags = {
    Name = var.alb_config.name
  }
}

resource "aws_lb_target_group" "this" {
  name     = "${substr(var.alb_config.name, 0, min(length(var.alb_config.name), 16))}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled             = true
    path                = var.alb_config.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.alb_config.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.asg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl enable httpd
    echo "ok" > /var/www/html/index.html
    echo "healthy" > /var/www/html/health
    systemctl start httpd
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

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.alb_config.name}-asg"
  desired_capacity          = 2
  max_size                  = 3
  min_size                  = 2
  vpc_zone_identifier       = local.subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.this.arn]

  tag {
    key                 = "Name"
    value               = "${var.alb_config.name}-asg-instance"
    propagate_at_launch = true
  }
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}