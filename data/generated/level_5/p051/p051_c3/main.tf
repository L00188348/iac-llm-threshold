variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "bucket_name" {
  type = string
}

variable "region" {
  type    = string
  default = null
}

data "aws_region" "current" {}

locals {
  aws_region = coalesce(var.region, data.aws_region.current.name)
  instance_name = "ec2-cloudwatch-agent"
}

resource "aws_iam_role" "ec2" {
  name = "${local.instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2" {
  name = "${local.instance_name}-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.instance_name}-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "ec2" {
  name        = "${local.instance_name}-sg"
  description = "Security group for EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnet" "default" {
  id = tolist(data.aws_subnet_ids.default.ids)[0]
}

resource "aws_instance" "ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids  = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    yum update -y
    yum install -y amazon-cloudwatch-agent

    cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWEOF'
    {
      "agent": {
        "run_as_user": "root"
      },
      "metrics": {
        "append_dimensions": {
          "InstanceId": "${aws:InstanceId}"
        },
        "metrics_collected": {
          "cpu": {
            "measurement": [
              "cpu_usage_idle",
              "cpu_usage_iowait",
              "cpu_usage_user",
              "cpu_usage_system"
            ],
            "metrics_collection_interval": 60,
            "totalcpu": true
          },
          "mem": {
            "measurement": [
              "mem_used_percent"
            ],
            "metrics_collection_interval": 60
          }
        }
      }
    }
    CWEOF

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s
  EOF

  tags = {
    Name = local.instance_name
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.instance_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x = 0
        y = 0
        width = 12
        height = 6
        properties = {
          title = "CPU Utilization"
          view = "timeSeries"
          region = local.aws_region
          period = 60
          stat = "Average"
          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              aws_instance.ec2.id
            ]
          ]
        }
      },
      {
        type = "metric"
        x = 12
        y = 0
        width = 12
        height = 6
        properties = {
          title = "Memory Usage"
          view = "timeSeries"
          region = local.aws_region
          period = 60
          stat = "Average"
          metrics = [
            [
              "CWAgent",
              "mem_used_percent",
              "InstanceId",
              aws_instance.ec2.id
            ]
          ]
        }
      }
    ]
  })
}