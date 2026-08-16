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
    Project = "iac-demo"
    Owner   = "platform"
  }
}

locals {
  user_objects = {
    for idx, name in var.user_list : name => {
      index = idx
      name  = name
      role  = lookup({
        alice = "admin"
        bob   = "developer"
      }, name, "viewer")
    }
  }

  role_defaults = {
    admin     = { policy_prefix = "AdministratorAccess", bucket_suffix = "admin" }
    developer  = { policy_prefix = "PowerUserAccess",      bucket_suffix = "dev" }
    viewer     = { policy_prefix = "ReadOnlyAccess",       bucket_suffix = "view" }
  }

  user_profiles = {
    for name, obj in local.user_objects : name => merge(
      {
        user_name     = obj.name
        display_index = obj.index
      },
      lookup(local.role_defaults, obj.role, {
        policy_prefix = "ReadOnlyAccess"
        bucket_suffix = "view"
      }),
      {
        bucket_name = lower(replace("${obj.name}-${lookup(local.role_defaults, obj.role, { bucket_suffix = "view" }).bucket_suffix}-bucket", "/[^a-z0-9-]/", "-"))
      }
    )
  }

  bucket_map = {
    for name, profile in local.user_profiles : name => {
      bucket_name = profile.bucket_name
      tags = merge(var.common_tags, {
        User = name
        Role = local.user_objects[name].role
      })
    }
  }
}

resource "aws_iam_user" "users" {
  for_each = local.user_profiles

  name = each.value.user_name
  tags = merge(var.common_tags, {
    User = each.key
    Role = local.user_objects[each.key].role
  })
}

resource "aws_iam_user_policy_attachment" "managed_policies" {
  for_each = local.user_profiles

  user       = aws_iam_user.users[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/${each.value.policy_prefix}"
}

resource "aws_s3_bucket" "user_buckets" {
  for_each = local.bucket_map

  bucket = each.value.bucket_name
  tags   = each.value.tags
}

resource "aws_s3_bucket_versioning" "user_buckets" {
  for_each = aws_s3_bucket.user_buckets

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_user_policy" "inline_access" {
  for_each = local.user_profiles

  name = "${each.key}-s3-access"
  user = aws_iam_user.users[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          aws_s3_bucket.user_buckets[each.key].arn
        ]
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.user_buckets[each.key].arn}/*"
        ]
      }
    ]
  })
}

output "iam_user_names" {
  value = [for u in aws_iam_user.users : u.name]
}

output "bucket_names" {
  value = [for b in aws_s3_bucket.user_buckets : b.bucket]
}

output "user_role_map" {
  value = { for name, obj in local.user_objects : name => obj.role }
}