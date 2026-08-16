variable "source_bucket_name" {
  type    = string
  default = "source-bucket"
}

variable "dest_bucket_name" {
  type    = string
  default = "dest-bucket"
}

resource "aws_s3_bucket" "source" {
  bucket = var.source_bucket_name
}

resource "aws_s3_bucket" "destination" {
  bucket = var.dest_bucket_name
}

resource "aws_iam_role" "replication" {
  name = "${var.source_bucket_name}-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "${var.source_bucket_name}-replication-policy"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSourceBucketList"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.source.arn
      },
      {
        Sid    = "AllowSourceObjectRead"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectVersionForReplication"
        ]
        Resource = "${aws_s3_bucket.source.arn}/logs/*"
      },
      {
        Sid    = "AllowDestinationReplicationWrite"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.destination.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [
    aws_s3_bucket.source,
    aws_s3_bucket.destination,
    aws_iam_role_policy.replication
  ]
}