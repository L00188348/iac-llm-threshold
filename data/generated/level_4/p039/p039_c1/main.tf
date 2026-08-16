variable "bastion_config" {
  type = object({
    subnet_id         = string
    security_group_ids = list(string)
    key_name          = string
    allowed_cidr      = string
  })
  default = {
    subnet_id         = ""
    security_group_ids = []
    key_name          = "test-key"
    allowed_cidr      = "10.0.0.0/16"
  }

  validation {
    condition     = can(cidrhost(var.bastion_config.allowed_cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}\\/[0-9]{1,2}$", var.bastion_config.allowed_cidr))
    error_message = "allowed_cidr must be a valid IPv4 CIDR."
  }
}

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

provider "aws" {
  region = "us-east-1"
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
  availability_zone       = "us-east-1a"

  tags = {
    Name = "bastion-public-subnet"
  }
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

resource "aws_default_security_group" "bastion" {
  vpc_id = aws_vpc.bastion.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_config.allowed_cidr]
  }

  egress {
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
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_config.allowed_cidr]
  }

  egress {
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
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = concat([aws_security_group.bastion.id, aws_default_security_group.bastion.id], var.bastion_config.security_group_ids)
  key_name               = var.bastion_config.key_name

  associate_public_ip_address = true

  tags = {
    Name = "bastion-host"
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name = "bastion-eip"
  }
}

resource "aws_eip_association" "bastion" {
  allocation_id = aws_eip.bastion.id
  instance_id   = aws_instance.bastion.id
}

output "vpc_id" {
  value = aws_vpc.bastion.id
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "instance_id" {
  value = aws_instance.bastion.id
}

output "eip_public_ip" {
  value = aws_eip.bastion.public_ip
}