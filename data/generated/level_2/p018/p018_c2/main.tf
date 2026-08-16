variable "key_name" {
  type    = string
  default = "test-key"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = tls_private_key.this.public_key_openssh
}

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type  = var.instance_type
  key_name       = aws_key_pair.this.key_name
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
}