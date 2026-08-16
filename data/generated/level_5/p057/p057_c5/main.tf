terraform {
  required_version = ">= 1.0.0"

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
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "enable_bucket" {
  description = "Whether to create the S3 bucket."
  type        = bool
  default     = true
}

variable "enable_lifecycle" {
  description = "Whether to attach lifecycle rules to the S3 bucket."
  type        = bool
  default     = true
}

variable "bucket_name" {
  description = "Base name for the S3 bucket."
  type        = string
  default     = "example-conditional-bucket"
}

locals {
  bucket_enabled   = var.enable_bucket
  lifecycle_enabled = var.enable_bucket && var.enable_lifecycle
  effective_bucket_name = local.bucket_enabled ? var.bucket_name : null
  lifecycle_rules = local.lifecycle_enabled ? [
    {
      id      = "expire-old-objects"
      enabled = true
      prefix  = ""
      expiration = {
        days = 30
      }
    }
  ] : []
}

resource "aws_s3_bucket" "this" {
  count  = var.enable_bucket ? 1 : 0
  bucket = "${var.bucket_name}-${terraform.workspace}"
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.enable_bucket && var.enable_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

output "bucket_name" {
  value       = try(aws_s3_bucket.this[0].bucket, null)
  description = "The created bucket name, or null if bucket creation is disabled."
}

output "lifecycle_enabled" {
  value       = local.lifecycle_enabled
  description = "Whether lifecycle configuration is enabled and applied."
}