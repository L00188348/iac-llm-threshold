variable "bucket_name" {
  type        = string
  default     = "my-app-data-bucket"
  description = "S3 bucket name."

  validation {
    condition     = length(var.bucket_name) >= 3 && can(regex("^[a-z0-9-]+$", var.bucket_name))
    error_message = "bucket_name must be at least 3 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "transition_days" {
  type        = number
  default     = 30
  description = "Number of days before transitioning objects to STANDARD_IA."

  validation {
    condition     = var.transition_days >= 30
    error_message = "transition_days must be at least 30."
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

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "transition-to-standard-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_days
      storage_class = "STANDARD_IA"
    }
  }
}