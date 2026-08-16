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

variable "user_overrides" {
  type = map(object({
    department = string
    role       = string
    suffix     = string
  }))
  default = {
    alice = {
      department = "engineering"
      role       = "admin"
      suffix     = "prod"
    }
    bob = {
      department = "finance"
      role       = "read-only"
      suffix     = "reports"
    }
  }
}

locals {
  base_user_data = {
    for user in var.user_list :
    user => {
      department = lookup(var.user_overrides, user, { department = "general", role = "poweruser", suffix = "data" }).department
      role       = lookup(var.user_overrides, user, { department = "general", role = "poweruser", suffix = "data" }).role
      suffix     = lookup(var.user_overrides, user, { department = "general", role = "poweruser", suffix = "data" }).suffix
    }
  }

  enriched_user_data = {
    for user, data in local.base_user_data :
    user => merge(
      data,
      {
        bucket_name = lower(format("%s-%s-%s", user, data.department, data.suffix))
        tags = merge(
          var.common_tags,
          {
            User       = user
            Department = data.department
            Role       = data.role
          }
        )
      }
    )
  }

  policy_arns = {
    admin      = "arn:aws:iam::aws:policy/AdministratorAccess"
    read-only  = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    poweruser  = "arn:aws:iam::aws:policy/PowerUserAccess"
    data       = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  }

  user_policies = {
    for user, data in local.enriched_user_data :
    user => lookup(local.policy_arns, data.role, local.policy_arns["read-only"])
  }
}

resource "aws_iam_user" "users" {
  for_each = local.enriched_user_data

  name = each.key
  tags = each.value.tags
}

resource "aws_iam_user_policy_attachment" "users" {
  for_each = local.user_policies

  user       = aws_iam_user.users[each.key].name
  policy_arn = each.value
}

resource "aws_s3_bucket" "user_buckets" {
  for_each = local.enriched_user_data

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

output "user_bucket_names" {
  value = {
    for user, bucket in aws_s3_bucket.user_buckets :
    user => bucket.bucket
  }
}

output "user_policy_arns" {
  value = local.user_policies
}