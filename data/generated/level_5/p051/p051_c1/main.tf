variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "example" {
  bucket = "example-ec2-s3-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_iam_role" "ec2" {
  name = "ec2-cloudwatch-agent-role"

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
  name = "ec2-s3-cloudwatch-policy"
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
          aws_s3_bucket.example.arn,
          "${aws_s3_bucket.example.arn}/*"
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
  name = "ec2-cloudwatch-agent-instance-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "ec2" {
  name        = "ec2-cloudwatch-agent-sg"
  description = "Allow SSH and outbound internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnet" "default" {
  id = tolist(data.aws_subnet_ids.default.ids)[0]
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "this" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id               = data.aws_subnet.default.id
  vpc_security_group_ids  = [aws_security_group.ec2.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              if command -v yum >/dev/null 2>&1; then
                yum update -y
                yum install -y amazon-cloudwatch-agent
              elif command -v apt-get >/dev/null 2>&1; then
                apt-get update -y
                apt-get install -y wget
                wget -O /tmp/amazon-cloudwatch-agent.deb https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
                dpkg -i /tmp/amazon-cloudwatch-agent.deb || apt-get -f install -y
              fi

              cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
              {
                "agent": {
                  "metrics_collection_interval": 60,
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
              JSON

              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                -s
              EOF

  tags = {
    Name = "cloudwatch-agent-instance"
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "ec2-performance-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.this.id]
          ]
          stat   = "Average"
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type = "metric"
        x    = 12
        y    = 0
        width = 12
        height = 6
        properties = {
          title  = "EC2 Memory Usage"
          region = data.aws_region.current.name
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.this.id]
          ]
          stat   = "Average"
          period = 300
          view   = "timeSeries"
        }
      }
    ]
  })
}