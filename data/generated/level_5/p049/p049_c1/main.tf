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
    rule_id       = optional(string)
  }))

  default = [
    {
      days         = 30
      storage_class = "STANDARD_IA"
      rule_id      = "transition-to-ia"
    },
    {
      days         = 90
      storage_class = "GLACIER"
      rule_id      = "transition-to-glacier"
    }
  ]
}

locals {
  lifecycle_rules_map = {
    for idx, rule in var.lifecycle_rules :
    coalesce(rule.rule_id, "rule-${idx}") => rule
  }
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
  for_each = {
    for idx, rule in var.lifecycle_rules :
    idx => rule
  }

  bucket = aws_s3_bucket.this.id
  name   = "tiering-${each.key}"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = each.value.days
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = local.lifecycle_rules_map
    content {
      id     = rule.key
      status = "Enabled"

      filter {}

      transition {
        days          = rule.value.days
        storage_class = rule.value.storage_class
      }
    }
  }
}