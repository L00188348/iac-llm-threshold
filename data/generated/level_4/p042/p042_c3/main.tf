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
    condition = (
      var.asg_config.min_size <= var.asg_config.desired_capacity &&
      var.asg_config.desired_capacity <= var.asg_config.max_size
    )
    error_message = "Validation failed: min_size <= desired_capacity <= max_size must hold."
  }
}

resource "aws_lb_target_group" "this" {
  name     = "${substr(var.asg_config.name, 0, 20)}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  owners = ["amazon"]

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
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.asg_config.instance_type

  update_default_version = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name                = var.asg_config.name
  min_size            = var.asg_config.min_size
  max_size            = var.asg_config.max_size
  desired_capacity    = var.asg_config.desired_capacity
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [
    coalesce(var.asg_config.target_group_arn, aws_lb_target_group.this.arn)
  ]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}