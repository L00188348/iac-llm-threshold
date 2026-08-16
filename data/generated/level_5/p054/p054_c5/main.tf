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
        value = "arn:aws:iam::123456789012:role/ExampleConsumerRole"
      }
    }
  })
}

locals {
  simulated_state = jsondecode(local_file.simulated_remote_state.content)

  remote_outputs = {
    bucket_name          = local.simulated_state.outputs.bucket_name.value
    allowed_principal_arn = local.simulated_state.outputs.allowed_principal_arn.value
  }
}

resource "aws_s3_bucket" "this" {
  bucket = local.remote_outputs.bucket_name
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowReadFromSimulatedRemotePrincipal"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.remote_outputs.allowed_principal_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}