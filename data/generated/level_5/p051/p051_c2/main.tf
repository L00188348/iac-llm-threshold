variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  bucket = "${data.aws_caller_identity.current.account_id}-ec2-metrics-logs"
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-cloudwatch-s3-role"

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

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2-cloudwatch-s3-policy"
  role = aws_iam_role.ec2_role.id

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
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
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

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-cloudwatch-s3-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-cloudwatch-sg"
  description = "Allow SSH and egress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
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

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "ec2" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              dnf update -y
              dnf install -y amazon-cloudwatch-agent amazon-linux-extras jq

              cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCFG'
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "metrics": {
                  "append_dimensions": {
                    "InstanceId": "${aws:InstanceId}"
                  },
                  "aggregation_dimensions": [
                    ["InstanceId"]
                  ],
                  "metrics_collected": {
                    "mem": {
                      "measurement": [
                        "mem_used_percent"
                      ],
                      "metrics_collection_interval": 60
                    },
                    "cpu": {
                      "measurement": [
                        "cpu_usage_idle",
                        "cpu_usage_user",
                        "cpu_usage_system"
                      ],
                      "totalcpu": true,
                      "metrics_collection_interval": 60
                    }
                  }
                }
              }
              CWCFG

              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                -s
              EOF

  tags = {
    Name = "ec2-cloudwatch-instance"
  }
}

resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = "ec2-cpu-memory-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "metric"
        x          = 0
        y          = 0
        width      = 12
        height     = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = data.aws_region.current.name
          stat   = "Average"
          period = 60
          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              aws_instance.ec2.id
            ]
          ]
          view = "timeSeries"
          stacked = false
        }
      },
      {
        type       = "metric"
        x          = 12
        y          = 0
        width      = 12
        height     = 6
        properties = {
          title  = "EC2 Memory Usage"
          region = data.aws_region.current.name
          stat   = "Average"
          period = 60
          metrics = [
            [
              "CWAgent",
              "mem_used_percent",
              "InstanceId",
              aws_instance.ec2.id
            ]
          ]
          view = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}