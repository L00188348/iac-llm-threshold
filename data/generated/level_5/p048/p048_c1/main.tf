terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
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

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "example" {
  bucket = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
}

resource "aws_dynamodb_table" "example" {
  name         = "${var.dynamodb_table_name_prefix}-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "local_file" "random_suffix" {
  filename = "${path.module}/random_suffix.txt"
  content  = random_id.suffix.hex
}

resource "terraform_data" "export_resource_outputs" {
  triggers_replace = {
    bucket_arn  = aws_s3_bucket.example.arn
    table_name   = aws_dynamodb_table.example.name
    random_seed  = random_id.suffix.hex
    suffix_file  = local_file.random_suffix.filename
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > "${path.module}/resource_outputs.txt" <<EOF
      s3_bucket_arn=${aws_s3_bucket.example.arn}
      dynamodb_table_name=${aws_dynamodb_table.example.name}
      random_suffix=${random_id.suffix.hex}
      EOF
    EOT
    interpreter = ["bash", "-c"]
  }
}

variable "bucket_name_prefix" {
  type    = string
  default = "example-bucket"
}

variable "dynamodb_table_name_prefix" {
  type    = string
  default = "example-table"
}