terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "local_file" "simulated_remote_state" {
  filename = "${path.module}/simulated-remote-state.json"
  content = jsonencode({
    outputs = {
      bucket_name = {
        value = "example-shared-bucket"
      }
      allowed_principal_arn = {
        value = "arn:aws:iam::123456789012:role/example-readonly-role"
      }
      source_account = {
        value = "123456789012"
      }
    }
  })
}

data "local_file" "simulated_remote_state" {
  filename   = local_file.simulated_remote_state.filename
  depends_on = [local_file.simulated_remote_state]
}

locals {
  remote_state = jsondecode(data.local_file.simulated_remote_state.content)
  bucket_name   = local.remote_state.outputs.bucket_name.value
  principal_arn = local.remote_state.outputs.allowed_principal_arn.value
  source_account = local.remote_state.outputs.source_account.value
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid     = "AllowReadFromSimulatedRemoteStatePrincipal"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.this.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [local.principal_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.source_account]
    }
  }

  statement {
    sid     = "AllowListBucketFromSimulatedRemoteStatePrincipal"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]

    principals {
      type        = "AWS"
      identifiers = [local.principal_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.source_account]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}