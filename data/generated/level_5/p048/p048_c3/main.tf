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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
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
  special = false
  upper   = false
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

resource "local_file" "random_suffix" {
  filename = "${path.module}/random_suffix.txt"
  content  = random_string.suffix.result
}

resource "terraform_data" "write_outputs" {
  depends_on = [
    aws_s3_bucket.example,
    aws_dynamodb_table.example,
    local_file.random_suffix
  ]

  input = {
    bucket_arn   = aws_s3_bucket.example.arn
    table_name   = aws_dynamodb_table.example.name
    random_value  = random_string.suffix.result
    output_file   = "${path.module}/resource_outputs.txt"
    suffix_file   = local_file.random_suffix.filename
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > "${self.input.output_file}" <<EOF
      s3_bucket_arn=${self.input.bucket_arn}
      dynamodb_table_name=${self.input.table_name}
      random_suffix=$(cat "${self.input.suffix_file}")
      EOF
    EOT
    interpreter = ["/bin/sh", "-c"]
  }
}

output "bucket_arn" {
  value = aws_s3_bucket.example.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.example.name
}

output "random_suffix" {
  value = random_string.suffix.result
}

output "random_suffix_file" {
  value = local_file.random_suffix.filename
}