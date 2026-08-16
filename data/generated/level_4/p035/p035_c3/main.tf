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
    vpc_cidr             = string
    public_subnet_cidrs  = list(string)
    private_subnet_cidrs = list(string)
    azs                  = list(string)
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
      can(cidrhost(var.network_config.vpc_cidr, 0)) &&
      alltrue([for cidr in var.network_config.public_subnet_cidrs : can(cidrhost(cidr, 0))]) &&
      alltrue([for cidr in var.network_config.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    )
    error_message = "network_config must have equal numbers of public_subnet_cidrs and azs, and all CIDR blocks must be valid."
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    ec2 = "http://localhost:4566"
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
    Name = "public-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    for idx, cidr in var.network_config.private_subnet_cidrs : idx => {
      cidr = cidr
      az   = var.network_config.azs[idx % length(var.network_config.azs)]
    }
  }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "private-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "public-rt"
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
    Name = "private-rt"
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
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}