terraform {
  required_version = ">= 1.5.0"

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

variable "bucket_name" {
  type    = string
  default = null
}

variable "lifecycle_rules" {
  type = list(object({
    days          = number
    storage_class  = string
    prefix         = optional(string)
    enabled        = optional(bool, true)
    expiration_days = optional(number)
  }))

  default = [
    {
      days         = 30
      storage_class = "STANDARD_IA"
      prefix        = "logs/"
      enabled       = true
    },
    {
      days         = 90
      storage_class = "GLACIER"
      prefix        = "archive/"
      enabled       = true
    }
  ]
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name != null ? var.bucket_name : null
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  for_each = {
    for idx, rule in var.lifecycle_rules : idx => rule
    if can(regex("(?i)INTELLIGENT_TIERING", rule.storage_class))
  }

  bucket = aws_s3_bucket.this.id
  name   = "intelligent-tiering-${each.key}"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = each.value.days
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = each.value.days + 90
  }

  filter {
    prefix = try(each.value.prefix, null)
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = {
      for idx, r in var.lifecycle_rules : idx => r
      if !can(regex("(?i)INTELLIGENT_TIERING", r.storage_class))
    }

    content {
      id     = "lifecycle-${rule.key}"
      status = try(rule.value.enabled, true) ? "Enabled" : "Disabled"

      filter {
        prefix = try(rule.value.prefix, null)
      }

      transition {
        days          = rule.value.days
        storage_class = rule.value.storage_class
      }

      dynamic "expiration" {
        for_each = try(rule.value.expiration_days, null) == null ? [] : [rule.value.expiration_days]
        content {
          days = expiration.value
        }
      }
    }
  }
}