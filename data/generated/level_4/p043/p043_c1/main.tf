terraform {
  required_version = ">= 1.3.0"

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

variable "env_config" {
  type = object({
    environment    = string
    vpc_cidr       = string
    instance_type  = string
    db_table_name  = string
    bucket_name    = string
  })

  default = {
    environment   = "dev"
    vpc_cidr      = "10.0.0.0/16"
    instance_type = "t3.micro"
    db_table_name = "dev-table"
    bucket_name   = "dev-bucket"
  }

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env_config.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }

  validation {
    condition     = can(regex("^t3\\..*", var.env_config.instance_type))
    error_message = "instance_type must match the pattern ^t3\\..*."
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.env_config.environment}-dev"
  az1         = data.aws_availability_zones.available.names[0]
  az2         = data.aws_availability_zones.available.names[1]
}

resource "aws_vpc" "main" {
  cidr_block           = var.env_config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
    Env  = var.env_config.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
    Env  = var.env_config.environment
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.env_config.vpc_cidr, 8, 0)
  availability_zone       = local.az1
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-a"
    Env  = var.env_config.environment
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.env_config.vpc_cidr, 8, 1)
  availability_zone       = local.az2
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-b"
    Env  = var.env_config.environment
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.env_config.vpc_cidr, 8, 10)
  availability_zone = local.az1

  tags = {
    Name = "${local.name_prefix}-private-a"
    Env  = var.env_config.environment
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.env_config.vpc_cidr, 8, 11)
  availability_zone = local.az2

  tags = {
    Name = "${local.name_prefix}-private-b"
    Env  = var.env_config.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
    Env  = var.env_config.environment
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Bastion host security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.env_config.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-bastion-sg"
    Env  = var.env_config.environment
  }
}

resource "aws_iam_role" "bastion" {
  name = "${local.name_prefix}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.env_config.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.bastion.name

  tags = {
    Name = "${local.name_prefix}-bastion"
    Env  = var.env_config.environment
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*x86_64-gp2"]
  }
}

resource "aws_dynamodb_table" "main" {
  name         = var.env_config.db_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = var.env_config.db_table_name
    Env  = var.env_config.environment
  }
}

resource "aws_s3_bucket" "main" {
  bucket = var.env_config.bucket_name

  tags = {
    Name = var.env_config.bucket_name
    Env  = var.env_config.environment
  }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}

output "public_subnet_b_id" {
  value = aws_subnet.public_b.id
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  value = aws_subnet.private_b.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "bastion_security_group_id" {
  value = aws_security_group.bastion.id
}

output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "bastion_iam_role_id" {
  value = aws_iam_role.bastion.id
}

output "bastion_instance_profile_id" {
  value = aws_iam_instance_profile.bastion.id
}

output "dynamodb_table_id" {
  value = aws_dynamodb_table.main.id
}

output "s3_bucket_id" {
  value = aws_s3_bucket.main.id
}