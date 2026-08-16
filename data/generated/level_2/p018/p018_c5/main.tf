terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

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

resource "tls_private_key" "ec2" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "ec2" {
  key_name   = var.key_name
  public_key = tls_private_key.ec2.public_key_openssh
}

resource "aws_instance" "ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ec2.key_name
  associate_public_ip_address = true

  tags = {
    Name = var.key_name
  }
}

resource "aws_eip" "ec2" {
  domain   = "vpc"
  instance = aws_instance.ec2.id

  tags = {
    Name = "${var.key_name}-eip"
  }
}

output "private_key_pem" {
  value     = tls_private_key.ec2.private_key_pem
  sensitive = true
}

output "public_key_openssh" {
  value = tls_private_key.ec2.public_key_openssh
}

output "instance_id" {
  value = aws_instance.ec2.id
}

output "eip_public_ip" {
  value = aws_eip.ec2.public_ip
}