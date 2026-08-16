variable "bucket_configs" {
  type = map(object({
    name             = string
    transition_days   = number
  }))
  default = {
    analytics = {
      name           = "analytics"
      transition_days = 30
    }
    warehouse = {
      name           = "warehouse"
      transition_days = 60
    }
    staging = {
      name           = "staging"
      transition_days = 90
    }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = var.bucket_configs

  bucket = each.value.name
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = var.bucket_configs

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "transition-to-standard-ia"
    status = "Enabled"

    transition {
      days          = each.value.transition_days
      storage_class = "STANDARD_IA"
    }
  }
}