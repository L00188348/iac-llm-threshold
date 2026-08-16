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

variable "enable_intelligent_tiering" {
  type    = bool
  default = true
}

locals {
  lifecycle_rules_by_key = {
    for idx, rule in var.lifecycle_rules : idx => rule
  }
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  dynamic "lifecycle_rule" {
    for_each = local.lifecycle_rules_by_key
    content {
      id      = "transition-${lifecycle_rule.key}"
      enabled = true

      transition {
        days          = lifecycle_rule.value.days
        storage_class  = lifecycle_rule.value.storage_class
      }

      dynamic "transition" {
        for_each = var.enable_intelligent_tiering ? [1] : []
        content {
          days          = 0
          storage_class  = "INTELLIGENT_TIERING"
        }
      }
    }
  }

  versioning {
    enabled = true
  }
}