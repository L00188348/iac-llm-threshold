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

  public_subnets = [
    for i in range(var.public_subnet_count) : {
      az   = local.availability_zones[i % length(local.availability_zones)]
      cidr = cidrsubnet(var.base_cidr, 8, i)
    }
  ]

  private_subnets = [
    for i in range(var.private_subnet_count) : {
      az   = local.availability_zones[i % length(local.availability_zones)]
      cidr = cidrsubnet(var.base_cidr, 8, i + var.public_subnet_count)
    }
  ]
}

resource "aws_vpc" "this" {
  cidr_block           = var.base_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "example-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = {
    for idx, subnet in local.public_subnets : idx => subnet
  }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    for idx, subnet in local.private_subnets : idx => subnet
  }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "private-${each.key}"
  }
}