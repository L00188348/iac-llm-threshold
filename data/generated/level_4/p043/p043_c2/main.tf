variable "env_config" {
  type = object({
    environment   = string
    vpc_cidr      = string
    instance_type = string
    db_table_name = string
    bucket_name   = string
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
    error_message = "instance_type must match the pattern ^t3\\..*"
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = var.env_config.environment
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.env_config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${local.name_prefix}-vpc"
    Environment = var.env_config.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${local.name_prefix}-igw"
    Environment = var.env_config.environment
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.env_config.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${local.name_prefix}-public-${count.index + 1}"
    Environment = var.env_config.environment
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.env_config.vpc_cidr, 8, count.index + 2)
  availability_zone = local.azs[count.index]

  tags = {
    Name        = "${local.name_prefix}-private-${count.index + 1}"
    Environment = var.env_config.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${local.name_prefix}-public-rt"
    Environment = var.env_config.environment
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-bastion-sg"
    Environment = var.env_config.environment
  }
}

resource "aws_key_pair" "bastion" {
  key_name   = "${local.name_prefix}-bastion-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0examplegeneratedkeyplaceholderterraformuser@localhost"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.env_config.instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.bastion.key_name

  tags = {
    Name        = "${local.name_prefix}-bastion"
    Environment = var.env_config.environment
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
    Name        = var.env_config.db_table_name
    Environment = var.env_config.environment
  }
}

resource "aws_s3_bucket" "main" {
  bucket = var.env_config.bucket_name

  tags = {
    Name        = var.env_config.bucket_name
    Environment = var.env_config.environment
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

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
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

output "dynamodb_table_id" {
  value = aws_dynamodb_table.main.id
}

output "s3_bucket_id" {
  value = aws_s3_bucket.main.id
}