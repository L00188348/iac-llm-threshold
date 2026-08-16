variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "volume_size" {
  type    = number
  default = 100
}

variable "volume_type" {
  type    = string
  default = "gp3"
}

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type  = var.instance_type
  availability_zone = data.aws_availability_zones.available.names[0]

  root_block_device {
    delete_on_termination = true
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_ebs_volume" "additional" {
  availability_zone = aws_instance.this.availability_zone
  size              = var.volume_size
  type              = var.volume_type
}

resource "aws_volume_attachment" "additional" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.additional.id
  instance_id = aws_instance.this.id
  force_detach = true
}