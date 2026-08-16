terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "bucket_name" {
  type    = string
  default = "example-lifecycle-bucket"
}

variable "lifecycle_rules" {
  type = list(object({
    days          = number
    storage_class  = string
  }))

  default = [
    {
      days         = 30
      storage_class = "STANDARD_IA"
    },
    {
      days         = 90
      storage_class = "GLACIER"
    }
  ]
}

locals {
  lifecycle_rules = { for idx, rule in var.lifecycle_rules : tostring(idx) => rule }
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  bucket  = aws_s3_bucket.this.id
  name    = "entire-bucket"
  status  = "Enabled"

  tiering {
    days        = 0
    access_tier = "ARCHIVE_ACCESS"
  }

  tiering {
    days        = 90
    access_tier = "DEEP_ARCHIVE_ACCESS"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "multiple-transitions"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = local.lifecycle_rules

      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}