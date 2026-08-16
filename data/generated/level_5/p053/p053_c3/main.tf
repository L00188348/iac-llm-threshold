terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

variable "user_list" {
  type    = list(string)
  default = ["alice", "bob", "carol"]
}

variable "common_tags" {
  type = map(string)
  default = {
    Project   = "iac-demo"
    ManagedBy = "terraform"
  }
}

locals {
  user_set = toset(var.user_list)

  user_configs = {
    for idx, user in var.user_list : user => {
      index = idx
      role  = idx == 0 ? "admin" : "developer"
      bucket_name = lower(join("-", [
        "demo",
        user,
        "bucket"
      ]))
      policy_actions = idx == 0 ? ["s3:*", "iam:ListUsers"] : ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      tags = merge(
        var.common_tags,
        {
          User      = user
          UserIndex = tostring(idx)
          Role      = idx == 0 ? "admin" : "developer"
        }
      )
    }
  }

  base_policy_statements = {
    admin = {
      Effect   = "Allow"
      Action   = ["s3:*", "iam:ListUsers"]
      Resource = ["*"]
    }
    developer = {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = ["*"]
    }
  }

  user_policy_map = {
    for user in var.user_list : user => merge(
      lookup(local.base_policy_statements, lookup(local.user_configs, user, {}).role, local.base_policy_statements.developer),
      {
        Name = "${user}-policy"
      }
    )
  }

  bucket_tags = {
    for user, cfg in local.user_configs : user => merge(
      var.common_tags,
      lookup(cfg, "tags", {}),
      {
        BucketName = cfg.bucket_name
      }
    )
  }
}

resource "aws_iam_user" "users" {
  for_each = local.user_set
  name     = each.value
  tags = merge(
    var.common_tags,
    {
      User = each.value
    }
  )
}

resource "aws_iam_policy" "user_policies" {
  for_each = local.user_policy_map

  name        = each.value.Name
  description = "Policy for ${each.key}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = each.value.Effect
        Action   = each.value.Action
        Resource = each.value.Resource
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "attachments" {
  for_each = local.user_policy_map

  user       = aws_iam_user.users[each.key].name
  policy_arn = aws_iam_policy.user_policies[each.key].arn
}

resource "aws_s3_bucket" "user_buckets" {
  for_each = local.user_configs
  bucket   = each.value.bucket_name

  tags = lookup(local.bucket_tags, each.key, var.common_tags)
}

resource "aws_s3_bucket_versioning" "user_buckets" {
  for_each = aws_s3_bucket.user_buckets

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "user_buckets" {
  for_each = aws_s3_bucket.user_buckets

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "iam_users" {
  value = {
    for k, u in aws_iam_user.users : k => u.name
  }
}

output "user_policies" {
  value = {
    for k, p in aws_iam_policy.user_policies : k => p.arn
  }
}

output "bucket_names" {
  value = {
    for k, b in aws_s3_bucket.user_buckets : k => b.bucket
  }
}