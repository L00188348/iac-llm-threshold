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
  region                      = var.aws_region
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = var.skip_credentials_validation
  skip_metadata_api_check     = var.skip_metadata_api_check
  skip_requesting_account_id   = var.skip_requesting_account_id
  s3_use_path_style           = var.s3_use_path_style
  endpoints                   = var.endpoints
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_access_key" {
  type    = string
  default = "test"
}

variable "aws_secret_key" {
  type    = string
  default = "test"
}

variable "skip_credentials_validation" {
  type    = bool
  default = true
}

variable "skip_metadata_api_check" {
  type    = bool
  default = true
}

variable "skip_requesting_account_id" {
  type    = bool
  default = true
}

variable "s3_use_path_style" {
  type    = bool
  default = true
}

variable "endpoints" {
  type = map(string)
  default = {
    s3 = "http://localhost:4566"
    iam = "http://localhost:4566"
  }
}

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

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.source_bucket_name}-replication-role"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role.json
}

data "aws_iam_policy_document" "replication" {
  statement {
    sid    = "SourceBucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.source.arn
    ]
  }

  statement {
    sid    = "SourceObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]

    resources = [
      "${aws_s3_bucket.source.arn}/logs/*"
    ]
  }

  statement {
    sid    = "DestinationBucketAccess"
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:ObjectOwnerOverrideToBucketOwner"
    ]

    resources = [
      "${aws_s3_bucket.destination.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "${var.source_bucket_name}-replication-policy"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "logs-replication"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = "STANDARD"
    }

    delete_marker_replication {
      status = "Enabled"
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.destination,
    aws_iam_role_policy.replication
  ]
}