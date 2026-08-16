terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "local_file" "random_suffix" {
  filename = "${path.module}/random_suffix.txt"
  content  = random_string.suffix.result
}

resource "aws_s3_bucket" "example" {
  bucket = "example-bucket-${random_string.suffix.result}"
}

resource "aws_dynamodb_table" "example" {
  name         = "example-table-${random_string.suffix.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "terraform_data" "write_outputs" {
  triggers_replace = {
    s3_bucket_arn = aws_s3_bucket.example.arn
    ddb_table_name = aws_dynamodb_table.example.name
    suffix         = random_string.suffix.result
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > "${path.module}/resource_outputs.txt" <<EOF
      s3_bucket_arn=${aws_s3_bucket.example.arn}
      dynamodb_table_name=${aws_dynamodb_table.example.name}
      random_suffix=${random_string.suffix.result}
      EOF
    EOT
  }

  depends_on = [
    aws_s3_bucket.example,
    aws_dynamodb_table.example,
    local_file.random_suffix
  ]
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.example.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.example.name
}

output "random_suffix" {
  value = random_string.suffix.result
}