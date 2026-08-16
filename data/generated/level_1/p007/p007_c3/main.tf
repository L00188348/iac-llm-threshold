variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "root_volume_size" {
  type    = number
  default = 30
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-instance-sg"
  description = "Security group for EC2 instance"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids  = [aws_security_group.ec2_sg.id]
  user_data              = <<-EOF
#!/bin/bash
set -e

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y nginx
  systemctl enable nginx
  systemctl start nginx
elif command -v yum >/dev/null 2>&1; then
  yum install -y nginx
  systemctl enable nginx
  systemctl start nginx
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx
  systemctl enable nginx
  systemctl start nginx
fi
EOF

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }
}