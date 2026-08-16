terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
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

variable "project_name" {
  type    = string
  default = "demo"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "local_file" "random_suffix" {
  filename        = "${path.module}/random_suffix.txt"
  content         = random_string.suffix.result
  file_permission = "0644"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.project_name}-bucket-${random_string.suffix.result}"
}

resource "aws_dynamodb_table" "table" {
  name         = "${var.project_name}-table-${random_string.suffix.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "terraform_data" "write_outputs" {
  triggers_replace = {
    bucket_arn   = aws_s3_bucket.bucket.arn
    table_name    = aws_dynamodb_table.table.name
    random_suffix = random_string.suffix.result
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/resource-outputs.txt <<EOF
      bucket_arn=${aws_s3_bucket.bucket.arn}
      table_name=${aws_dynamodb_table.table.name}
      random_suffix=${random_string.suffix.result}
      EOF
    EOT
  }
}

output "bucket_arn" {
  value = aws_s3_bucket.bucket.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.table.name
}

output "random_suffix_file" {
  value = local_file.random_suffix.filename
}

output "resource_outputs_file" {
  value = "${path.module}/resource-outputs.txt"
}