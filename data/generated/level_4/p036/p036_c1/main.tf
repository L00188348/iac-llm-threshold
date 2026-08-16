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

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  create_network = var.alb_config.vpc_id == ""
  vpc_id         = local.create_network ? aws_vpc.this[0].id : var.alb_config.vpc_id
  subnet_ids     = local.create_network ? aws_subnet.this[*].id : var.alb_config.subnet_ids
  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  count                = local.create_network ? 1 : 0
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.alb_config.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  count  = local.create_network ? 1 : 0
  vpc_id = aws_vpc.this[0].id

  tags = {
    Name = "${var.alb_config.name}-igw"
  }
}

resource "aws_subnet" "this" {
  count                   = local.create_network ? 2 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = cidrsubnet(aws_vpc.this[0].cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.alb_config.name}-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "this" {
  count  = local.create_network ? 1 : 0
  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = {
    Name = "${var.alb_config.name}-rt"
  }
}

resource "aws_route_table_association" "this" {
  count          = local.create_network ? 2 : 0
  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = aws_route_table.this[0].id
}

resource "aws_security_group" "alb" {
  name        = "${var.alb_config.name}-alb-sg"
  description = "ALB security group"
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
}

resource "aws_security_group" "asg" {
  name        = "${var.alb_config.name}-asg-sg"
  description = "ASG security group"
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
}

resource "aws_lb" "this" {
  name               = var.alb_config.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids
}

resource "aws_lb_target_group" "this" {
  name     = substr("${var.alb_config.name}-tg", 0, 32)
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled             = true
    path                = var.alb_config.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
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

  vpc_security_group_ids = [aws_security_group.asg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y || yum install -y nginx
              systemctl enable nginx
              echo "ok" > /usr/share/nginx/html/index.html
              echo "ok" > /usr/share/nginx/html/health
              systemctl start nginx
              EOF
  )
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

resource "aws_autoscaling_group" "this" {
  name                = "${var.alb_config.name}-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = local.subnet_ids

  target_group_arns = [aws_lb_target_group.this.arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.alb_config.name}-asg-instance"
    propagate_at_launch = true
  }
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}