terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
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

variable "simulated_state_file" {
  type    = string
  default = "${path.module}/simulated_outputs.json"
}

resource "local_file" "simulated_state" {
  filename = var.simulated_state_file
  content = jsonencode({
    outputs = {
      bucket_name = {
        value = "example-simulated-bucket"
      }
      allowed_principal_arn = {
        value = "arn:aws:iam::123456789012:role/example-role"
      }
    }
  })
}

data "local_file" "simulated_state" {
  filename   = local_file.simulated_state.filename
  depends_on = [local_file.simulated_state]
}

locals {
  simulated_outputs = jsondecode(data.local_file.simulated_state.content).outputs
  bucket_name       = local.simulated_outputs.bucket_name.value
  principal_arn     = local.simulated_outputs.allowed_principal_arn.value
}

resource "aws_s3_bucket" "example" {
  bucket = local.bucket_name
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowReadFromSimulatedPrincipal"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.principal_arn]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.example.arn}/*"
    ]
  }

  statement {
    sid    = "AllowListBucketFromSimulatedPrincipal"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.principal_arn]
    }

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.example.arn
    ]
  }
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.example.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}