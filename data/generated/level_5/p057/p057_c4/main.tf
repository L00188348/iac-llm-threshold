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

variable "enable_bucket" {
  type    = bool
  default = true
}

variable "enable_lifecycle" {
  type    = bool
  default = true
}

variable "bucket_name" {
  type    = string
  default = null
}

locals {
  create_bucket    = var.enable_bucket ? 1 : 0
  create_lifecycle = var.enable_bucket && var.enable_lifecycle ? 1 : 0
  effective_bucket_name = coalesce(
    var.bucket_name,
    "example-${terraform.workspace}-${substr(replace(uuid(), "-", ""), 0, 8)}"
  )
  lifecycle_expiration_days = var.enable_lifecycle ? 30 : 0
}

resource "aws_s3_bucket" "this" {
  count  = local.create_bucket
  bucket = local.effective_bucket_name
}

resource "aws_s3_bucket_versioning" "this" {
  count  = local.create_bucket
  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = local.create_lifecycle
  bucket = aws_s3_bucket.this[0].id

  rule {
    id     = "expire-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = local.lifecycle_expiration_days
    }
  }
}

output "bucket_id" {
  value       = try(aws_s3_bucket.this[0].id, null)
  description = "The created bucket ID, or null if bucket creation is disabled."
}

output "lifecycle_enabled" {
  value       = var.enable_bucket && var.enable_lifecycle
  description = "Whether lifecycle configuration is enabled."
}