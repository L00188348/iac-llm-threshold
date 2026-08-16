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

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type
  user_data     = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    if command -v dnf >/dev/null 2>&1; then
      dnf update -y
      dnf install -y nginx
      systemctl enable nginx
      systemctl start nginx
    elif command -v yum >/dev/null 2>&1; then
      yum update -y
      yum install -y nginx
      systemctl enable nginx
      systemctl start nginx
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update -y
      apt-get install -y nginx
      systemctl enable nginx
      systemctl start nginx
    fi
  EOF

  root_block_device {
    volume_type = "gp3"
    volume_size  = var.root_volume_size
  }
}