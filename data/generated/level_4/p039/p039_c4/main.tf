terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "bastion_config" {
  type = object({
    subnet_id          = string
    security_group_ids = list(string)
    key_name           = string
    allowed_cidr       = string
  })
  default = {
    subnet_id          = ""
    security_group_ids = []
    key_name           = "test-key"
    allowed_cidr       = "10.0.0.0/16"
  }

  validation {
    condition = can(cidrhost(var.bastion_config.allowed_cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$", var.bastion_config.allowed_cidr))
    error_message = "allowed_cidr must be a valid IPv4 CIDR."
  }
}

resource "aws_vpc" "bastion" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "bastion-vpc"
  }
}

resource "aws_internet_gateway" "bastion" {
  vpc_id = aws_vpc.bastion.id

  tags = {
    Name = "bastion-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.bastion.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "bastion-public-subnet"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.bastion.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.bastion.id
  }

  tags = {
    Name = "bastion-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.bastion.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_config.allowed_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-default-sg"
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.bastion.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_config.allowed_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = concat([aws_default_security_group.default.id, aws_security_group.bastion.id], var.bastion_config.security_group_ids)
  key_name                    = var.bastion_config.key_name
  associate_public_ip_address = true

  tags = {
    Name = "bastion-host"
  }
}

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name = "bastion-eip"
  }
}