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
  type    = bool
  default = true
}

variable "enable_lifecycle" {
  type    = bool
  default = true
}

variable "bucket_name_prefix" {
  type    = string
  default = "example-conditional-bucket"
}

locals {
  bucket_name     = var.enable_bucket ? "${var.bucket_name_prefix}-${random_id.bucket_suffix[0].hex}" : null
  lifecycle_rules = var.enable_bucket && var.enable_lifecycle ? [
    {
      id      = "expire-old-objects"
      enabled = true
      filter  = {}
      expiration = {
        days = 30
      }
    }
  ] : []
}

resource "random_id" "bucket_suffix" {
  count       = var.enable_bucket ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  count  = var.enable_bucket ? 1 : 0
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "this" {
  count  = var.enable_bucket ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.enable_bucket && var.enable_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  dynamic "rule" {
    for_each = local.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {}

      expiration {
        days = rule.value.expiration.days
      }
    }
  }
}