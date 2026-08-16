variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "bucket_name" {
  description = "S3 bucket name the instance can read from"
  type        = string
  default     = "example-bucket"
}

resource "aws_cloudwatch_log_group" "instance" {
  name              = "/ec2/cloudwatch-agent"
  retention_in_days = 14
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "ec2-cloudwatch-s3-role"
  assume_role_policy  = data.aws_iam_policy_document.ec2_assume_role.json
  managed_policy_arns = []
}

data "aws_iam_policy_document" "ec2_permissions" {
  statement {
    sid = "AllowS3Read"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.bucket_name}",
      "arn:aws:s3:::${var.bucket_name}/*",
    ]
  }

  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
    ]
    resources = [
      aws_cloudwatch_log_group.instance.arn,
      "${aws_cloudwatch_log_group.instance.arn}:*",
    ]
  }

  statement {
    sid = "AllowCloudWatchMetrics"
    actions = [
      "cloudwatch:PutMetricData",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ec2" {
  name   = "ec2-cloudwatch-s3-inline"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-cloudwatch-s3-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "ec2" {
  name        = "ec2-cloudwatch-sg"
  description = "Security group for EC2 instance"
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

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnet" "default" {
  id = tolist(data.aws_subnet_ids.default.ids)[0]
}

resource "aws_instance" "ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail

yum update -y || dnf update -y || true

if command -v yum >/dev/null 2>&1; then
  yum install -y amazon-cloudwatch-agent
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y amazon-cloudwatch-agent
fi

cat >/opt/aws/amazon-cloudwatch-agent/bin/config.json <<'CWEOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "EC2/Custom",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "totalcpu": true,
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${aws_cloudwatch_log_group.instance.name}",
            "log_stream_name": "{instance_id}/messages"
          }
        ]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json \
  -s
EOF

  tags = {
    Name = "cloudwatch-s3-ec2"
  }
}

resource "aws_cloudwatch_dashboard" "ec2" {
  dashboard_name = "ec2-cpu-memory-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "CPU Usage"
          region = data.aws_region.current.name
          metrics = [
            ["EC2/Custom", "cpu_usage_idle", "InstanceId", aws_instance.ec2.id, { stat = "Average" }],
            [".", "cpu_usage_user", ".", ".", { stat = "Average" }],
            [".", "cpu_usage_system", ".", ".", { stat = "Average" }]
          ]
          period = 60
          view   = "timeSeries"
          stacked = false
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Memory Usage"
          region = data.aws_region.current.name
          metrics = [
            ["EC2/Custom", "mem_used_percent", "InstanceId", aws_instance.ec2.id, { stat = "Average" }]
          ]
          period = 60
          view   = "timeSeries"
          stacked = false
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
}

data "aws_region" "current" {}