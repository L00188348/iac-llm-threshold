terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "local_file" "simulated_remote_state" {
  filename = "${path.module}/simulated_remote_state.json"
  content = jsonencode({
    outputs = {
      allowed_principal_arns = {
        value = [
          "arn:aws:iam::123456789012:role/ExampleAppRole",
          "arn:aws:iam::123456789012:user/ExampleUser"
        ]
      }
      bucket_name = {
        value = "example-simulated-state-bucket"
      }
    }
  })
}

locals {
  simulated_state = jsondecode(local_file.simulated_remote_state.content)
  allowed_principal_arns = try(
    local.simulated_state.outputs.allowed_principal_arns.value,
    []
  )
  bucket_name = try(
    local.simulated_state.outputs.bucket_name.value,
    "example-simulated-state-bucket"
  )
}

resource "aws_s3_bucket" "example" {
  bucket = local.bucket_name
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowReadFromSimulatedOutputs"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = local.allowed_principal_arns
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.example.arn,
      "${aws_s3_bucket.example.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.example.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}