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

resource "aws_instance" "example" {
  ami           = var.ami_id
  instance_type = var.instance_type

  root_block_device {
    delete_on_termination = true
  }
}

resource "aws_ebs_volume" "additional" {
  availability_zone = aws_instance.example.availability_zone
  size              = var.volume_size
  type              = var.volume_type
}

resource "aws_volume_attachment" "additional" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.additional.id
  instance_id = aws_instance.example.id
  force_detach = true
}