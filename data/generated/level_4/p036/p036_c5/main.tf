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

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  vpc_id     = var.alb_config.vpc_id != "" ? var.alb_config.vpc_id : aws_vpc.main[0].id
  subnet_ids = length(var.alb_config.subnet_ids) > 0 ? var.alb_config.subnet_ids : aws_subnet.public[*].id
}

resource "aws_vpc" "main" {
  count                = var.alb_config.vpc_id == "" ? 1 : 0
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.alb_config.name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  count  = var.alb_config.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.alb_config.name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = var.alb_config.vpc_id == "" && length(var.alb_config.subnet_ids) == 0 ? 2 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch  = true

  tags = {
    Name = "${var.alb_config.name}-public-${count.index}"
  }
}

resource "aws_route_table" "public" {
  count  = var.alb_config.vpc_id == "" && length(var.alb_config.subnet_ids) == 0 ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.alb_config.name}-public-rt"
  }
}

resource "aws_route" "internet_access" {
  count                  = var.alb_config.vpc_id == "" && length(var.alb_config.subnet_ids) == 0 ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route_table_association" "public" {
  count          = var.alb_config.vpc_id == "" && length(var.alb_config.subnet_ids) == 0 ? 2 : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "alb" {
  name        = "${var.alb_config.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.alb_config.name}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.alb_config.name}-app-sg"
  description = "Application security group"
  vpc_id      = local.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.alb_config.name}-app-sg"
  }
}

resource "aws_lb" "this" {
  name               = var.alb_config.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  tags = {
    Name = var.alb_config.name
  }
}

resource "aws_lb_target_group" "this" {
  name        = substr("${var.alb_config.name}-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.alb_config.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "${var.alb_config.name}-tg"
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

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.alb_config.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y nginx1
              systemctl enable nginx
              cat >/usr/share/nginx/html/index.html <<HTML
              <html><body><h1>OK</h1></body></html>
              HTML
              cat >/etc/nginx/conf.d/default.conf <<CONF
              server {
                  listen       80 default_server;
                  listen       [::]:80 default_server;
                  server_name  _;
                  root         /usr/share/nginx/html;
                  index        index.html;
                  location / {
                      try_files $uri $uri/ =404;
                  }
                  location ${var.alb_config.health_check_path} {
                      access_log off;
                      return 200 "ok\n";
                      add_header Content-Type text/plain;
                  }
              }
              CONF
              systemctl restart nginx
              EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.alb_config.name}-instance"
    }
  }
}

resource "aws_autoscaling_group" "this" {
  name                = "${var.alb_config.name}-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = local.subnet_ids
  target_group_arns   = [aws_lb_target_group.this.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

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