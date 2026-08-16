terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "enable_bucket" {
  description = "Whether to create the S3 bucket."
  type        = bool
  default     = true
}

variable "enable_lifecycle" {
  description = "Whether to attach lifecycle configuration to the S3 bucket."
  type        = bool
  default     = true
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name."
  type        = string
  default     = "example-conditional-bucket"
}

locals {
  create_bucket    = var.enable_bucket
  create_lifecycle = var.enable_bucket && var.enable_lifecycle
  bucket_name      = "${var.bucket_name_prefix}-${random_id.bucket_suffix[0].hex}"
}

resource "random_id" "bucket_suffix" {
  count       = local.create_bucket ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  count  = local.create_bucket ? 1 : 0
  bucket = local.bucket_name

  tags = {
    ManagedBy = "Terraform"
    Enabled   = tostring(var.enable_bucket)
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = local.create_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  rule {
    id     = "default-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

output "bucket_id" {
  value       = try(aws_s3_bucket.this[0].id, null)
  description = "The ID of the bucket when created."
}

output "bucket_arn" {
  value       = try(aws_s3_bucket.this[0].arn, null)
  description = "The ARN of the bucket when created."
}

output "lifecycle_enabled" {
  value       = local.create_lifecycle
  description = "Whether lifecycle configuration was created."
}