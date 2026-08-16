variable "bucket_name" {
  type    = string
  default = "example-lifecycle-bucket"
}

variable "lifecycle_rules" {
  type = list(object({
    days          = number
    storage_class = string
  }))

  default = [
    {
      days          = 30
      storage_class = "STANDARD_IA"
    },
    {
      days          = 90
      storage_class = "GLACIER"
    }
  ]
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
  bucket = aws_s3_bucket.this.id
  name   = "default"

  status = "Enabled"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = { for idx, r in var.lifecycle_rules : idx => r }

    content {
      id     = "transition-${rule.key}"
      status = "Enabled"

      filter {}

      transition {
        days          = rule.value.days
        storage_class = rule.value.storage_class
      }
    }
  }
}