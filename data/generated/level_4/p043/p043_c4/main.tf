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
    error_message = "instance_type must match ^t3\\..*."
  }
}

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

resource "aws_vpc" "main" {
  cidr_block           = var.env_config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.env_config.environment}-vpc"
    Environment = var.env_config.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.env_config.environment}-igw"
    Environment = var.env_config.environment
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.env_config.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.env_config.environment}-public-subnet"
    Environment = var.env_config.environment
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.env_config.environment}-public-rt"
    Environment = var.env_config.environment
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "bastion" {
  name        = "${var.env_config.environment}-bastion-sg"
  description = "Security group for bastion host"
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
    Name        = "${var.env_config.environment}-bastion-sg"
    Environment = var.env_config.environment
  }
}

resource "aws_iam_role" "ec2" {
  name = "${var.env_config.environment}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.env_config.environment}-bastion-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.env_config.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name

  tags = {
    Name        = "${var.env_config.environment}-bastion"
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

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "route_table_id" {
  value = aws_route_table.public.id
}

output "security_group_id" {
  value = aws_security_group.bastion.id
}

output "iam_role_id" {
  value = aws_iam_role.ec2.id
}

output "iam_instance_profile_id" {
  value = aws_iam_instance_profile.ec2.id
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