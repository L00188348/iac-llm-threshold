terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
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

variable "simulation_file_path" {
  type    = string
  default = "${path.module}/simulated-remote-state.json"
}

resource "local_file" "simulated_remote_state" {
  filename = var.simulation_file_path
  content = jsonencode({
    outputs = {
      account_id  = "123456789012"
      allowed_arn = "arn:aws:iam::123456789012:role/example-role"
      bucket_name = "example-shared-bucket"
    }
  })
}

locals {
  simulated_remote_state = jsondecode(local_file.simulated_remote_state.content)

  remote_outputs = local.simulated_remote_state.outputs
}

resource "aws_s3_bucket" "this" {
  bucket = local.remote_outputs.bucket_name
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowSpecificPrincipal"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.remote_outputs.allowed_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.this.arn}/*"
    ]
  }

  statement {
    sid    = "AllowListBucket"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.remote_outputs.allowed_arn]
    }

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.this.arn
    ]
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}