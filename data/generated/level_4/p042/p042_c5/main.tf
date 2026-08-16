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
    desired_capacity = 2
    instance_type    = "t3.micro"
    target_group_arn = ""
  }

  validation {
    condition     = var.asg_config.min_size <= var.asg_config.desired_capacity && var.asg_config.desired_capacity <= var.asg_config.max_size
    error_message = "asg_config must satisfy min_size <= desired_capacity <= max_size."
  }
}

resource "aws_lb_target_group" "this" {
  name     = substr("${var.asg_config.name}-tg", 0, 32)
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}

data "aws_vpc" "default" {
  default = true
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
  name_prefix   = "${var.asg_config.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.asg_config.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = []
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

  target_group_arns = [
    aws_lb_target_group.this.arn
  ]
}

data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}