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
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "enable_bucket" {
  type        = bool
  default     = true
  description = "Whether to create the S3 bucket"
}

variable "enable_lifecycle" {
  type        = bool
  default     = true
  description = "Whether to attach lifecycle rules to the S3 bucket"
}

variable "bucket_name" {
  type        = string
  default     = null
  description = "Optional explicit bucket name"
}

locals {
  bucket_enabled    = var.enable_bucket
  lifecycle_enabled = local.bucket_enabled && var.enable_lifecycle
  computed_bucket_name = coalesce(
    var.bucket_name,
    "example-${random_id.bucket_suffix[0].hex}"
  )
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

resource "random_id" "bucket_suffix" {
  count       = var.enable_bucket && var.bucket_name == null ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  count  = var.enable_bucket ? 1 : 0
  bucket = local.computed_bucket_name
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = local.lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  dynamic "rule" {
    for_each = local.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      expiration {
        days = rule.value.expiration.days
      }
    }
  }
}

output "bucket_id" {
  value       = try(aws_s3_bucket.this[0].id, null)
  description = "The created bucket ID, if enabled"
}

output "lifecycle_configuration_id" {
  value       = try(aws_s3_bucket_lifecycle_configuration.this[0].id, null)
  description = "The lifecycle configuration ID, if enabled"
}