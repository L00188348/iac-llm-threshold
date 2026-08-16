terraform {
  required_version = ">= 1.5.0"

  required_providers {
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

provider "random" {}
provider "local" {}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "local_file" "random_suffix" {
  filename = "${path.module}/random_suffix.txt"
  content  = random_string.suffix.result
}

resource "aws_s3_bucket" "example" {
  bucket = "example-${random_string.suffix.result}"
}

resource "aws_dynamodb_table" "example" {
  name           = "example-table-${random_string.suffix.result}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "terraform_data" "export_outputs" {
  input = {
    bucket_arn   = aws_s3_bucket.example.arn
    table_name   = aws_dynamodb_table.example.name
    random_suffix = random_string.suffix.result
  }

  provisioner "local-exec" {
    command = <<EOT
cat > ${path.module}/resource-outputs.txt <<EOF
bucket_arn=${aws_s3_bucket.example.arn}
table_name=${aws_dynamodb_table.example.name}
random_suffix=${random_string.suffix.result}
EOF
EOT
  }

  depends_on = [
    local_file.random_suffix,
    aws_s3_bucket.example,
    aws_dynamodb_table.example
  ]
}

output "bucket_arn" {
  value = aws_s3_bucket.example.arn
}

output "table_name" {
  value = aws_dynamodb_table.example.name
}

output "random_suffix_file" {
  value = local_file.random_suffix.filename
}

output "exported_outputs_file" {
  value = "${path.module}/resource-outputs.txt"
}