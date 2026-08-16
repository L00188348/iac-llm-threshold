terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "user_list" {
  type        = list(string)
  description = "List of IAM user names to create."
  default     = ["alice", "bob", "carol"]
}

variable "default_tags" {
  type        = map(string)
  description = "Base tags applied to all resources."
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

variable "user_overrides" {
  type        = map(map(string))
  description = "Per-user tag overrides."
  default = {
    alice = {
      Team = "analytics"
    }
    bob = {
      Team = "platform"
    }
  }
}

variable "bucket_suffixes" {
  type        = map(string)
  description = "Optional bucket suffixes per user."
  default = {
    alice = "docs"
    bob   = "assets"
  }
}

locals {
  users = toset(var.user_list)

  user_base_config = {
    for u in local.users : u => {
      user_name = u
      bucket_name = lower(replace("${u}-${lookup(var.bucket_suffixes, u, "data")}", "_", "-"))
      tags = merge(
        var.default_tags,
        lookup(var.user_overrides, u, {}),
        {
          Owner = u
        }
      )
    }
  }

  user_policy_documents = {
    for u, cfg in local.user_base_config : u => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "AllowListOwnBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::${cfg.bucket_name}"]
        },
        {
          Sid      = "AllowBucketObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = ["arn:aws:s3:::${cfg.bucket_name}/*"]
        }
      ]
    })
  }
}

resource "aws_iam_user" "users" {
  for_each = local.user_base_config

  name = each.value.user_name
  tags = each.value.tags
}

resource "aws_s3_bucket" "user_buckets" {
  for_each = local.user_base_config

  bucket = each.value.bucket_name
  tags   = each.value.tags
}

resource "aws_iam_policy" "user_bucket_policy" {
  for_each = local.user_policy_documents

  name        = "${each.key}-bucket-access"
  description = "Policy granting access to ${each.key}'s S3 bucket."
  policy      = each.value
}

resource "aws_iam_user_policy_attachment" "attachments" {
  for_each = local.user_base_config

  user       = aws_iam_user.users[each.key].name
  policy_arn = aws_iam_policy.user_bucket_policy[each.key].arn
}

output "iam_users" {
  value = {
    for k, v in aws_iam_user.users : k => v.name
  }
}

output "bucket_names" {
  value = {
    for k, v in aws_s3_bucket.user_buckets : k => v.bucket
  }
}

output "combined_user_metadata" {
  value = {
    for u, cfg in local.user_base_config : u => merge(
      cfg,
      {
        policy_arn = aws_iam_policy.user_bucket_policy[u].arn
      }
    )
  }
}