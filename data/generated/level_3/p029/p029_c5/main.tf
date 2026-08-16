variable "base_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_count" {
  type    = number
  default = 2
}

variable "private_subnet_count" {
  type    = number
  default = 2
}

locals {
  availability_zones = ["us-east-1a", "us-east-1b"]
  total_subnet_count = var.public_subnet_count + var.private_subnet_count
  subnet_newbits     = 8
}

resource "aws_vpc" "main" {
  cidr_block           = var.base_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public" {
  count = var.public_subnet_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.base_cidr, local.subnet_newbits, count.index)
  availability_zone = local.availability_zones[count.index % length(local.availability_zones)]

  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = var.private_subnet_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.base_cidr, local.subnet_newbits, var.public_subnet_count + count.index)
  availability_zone = local.availability_zones[count.index % length(local.availability_zones)]

  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-${count.index + 1}"
    Tier = "private"
  }
}