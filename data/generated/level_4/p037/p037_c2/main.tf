variable "ecs_config" {
  type = object({
    cluster_name    = string
    task_family     = string
    container_image = string
    cpu             = string
    memory          = string
    desired_count    = number
  })

  default = {
    cluster_name    = "test-cluster"
    task_family     = "test-task"
    container_image = "nginx:latest"
    cpu             = "256"
    memory          = "512"
    desired_count   = 2
  }

  validation {
    condition = contains(["256", "512", "1024"], var.ecs_config.cpu) && contains(["512", "1024", "2048", "3072"], var.ecs_config.memory)
    error_message = "cpu and memory must be valid EC2 task sizes. Supported examples include cpu values 256, 512, 1024 and memory values 512, 1024, 2048, 3072."
  }
}

resource "aws_ecs_cluster" "this" {
  name = var.ecs_config.cluster_name
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.ecs_config.cluster_name}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection  = "DISABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.ecs_config.cluster_name}-ecs-task-execution"

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

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.ecs_config.task_family
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = var.ecs_config.cpu
  memory                   = var.ecs_config.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.ecs_config.container_image
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.ecs_config.cluster_name}-ecs-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
  EOF
  )
}

resource "aws_iam_role" "ecs_instance" {
  name = "${var.ecs_config.cluster_name}-ecs-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "${var.ecs_config.cluster_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.ecs_config.cluster_name}-ecs-sg"
  description = "Security group for ECS instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_autoscaling_group" "ecs" {
  name_prefix         = "${var.ecs_config.cluster_name}-asg-"
  vpc_zone_identifier = data.aws_subnets.default.ids
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.ecs_config.cluster_name}-ecs-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ecs_service" "this" {
  name            = "${var.ecs_config.cluster_name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.ecs_config.desired_count

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "service_name" {
  value = aws_ecs_service.this.name
}