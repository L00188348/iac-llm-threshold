variable "cache_config" {
  type = object({
    bucket_name                = string
    versioning_enabled         = bool
    lifecycle_transition_days   = number
  })

  default = {
    bucket_name              = "cache-bucket"
    versioning_enabled       = true
    lifecycle_transition_days = 30
  }

  validation {
    condition     = var.cache_config.lifecycle_transition_days >= 30
    error_message = "lifecycle_transition_days must be at least 30."
  }
}

resource "aws_s3_bucket" "cache" {
  bucket = var.cache_config.bucket_name
}

resource "aws_s3_bucket_versioning" "cache" {
  bucket = aws_s3_bucket.cache.id

  versioning_configuration {
    status = var.cache_config.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id

  rule {
    id     = "standard-ia-transition"
    status = "Enabled"

    transition {
      days          = var.cache_config.lifecycle_transition_days
      storage_class  = "STANDARD_IA"
    }
  }
}

output "bucket_name" {
  value = aws_s3_bucket.cache.bucket
}