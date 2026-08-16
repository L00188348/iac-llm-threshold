terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "network_config" {
  type = object({
    vpc_cidr              = string
    public_subnet_cidrs   = list(string)
    private_subnet_cidrs  = list(string)
    azs                   = list(string)
  })

  default = {
    vpc_cidr             = "10.0.0.0/16"
    public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
    azs                  = ["us-east-1a", "us-east-1b"]
  }

  validation {
    condition = (
      length(var.network_config.public_subnet_cidrs) == length(var.network_config.azs) &&
      can(cidrnetmask(var.network_config.vpc_cidr)) &&
      alltrue([for cidr in var.network_config.public_subnet_cidrs : can(cidrnetmask(cidr))]) &&
      alltrue([for cidr in var.network_config.private_subnet_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "network_config must have equal numbers of public_subnet_cidrs and azs, and all CIDR values must be valid CIDR notation."
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.network_config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "localstack-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "localstack-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = {
    for idx, cidr in var.network_config.public_subnet_cidrs : idx => {
      cidr = cidr
      az   = var.network_config.azs[idx]
    }
  }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "localstack-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    for idx, cidr in var.network_config.private_subnet_cidrs : idx => {
      cidr = cidr
    }
  }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = var.network_config.azs[min(each.key, length(var.network_config.azs) - 1)]
  map_public_ip_on_launch = false

  tags = {
    Name = "localstack-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id  = aws_internet_gateway.this.id
  }

  tags = {
    Name = "localstack-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "localstack-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  value = [for subnet in aws_subnet.private : subnet.id]
}