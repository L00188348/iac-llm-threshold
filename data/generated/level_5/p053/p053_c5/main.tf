variable "user_list" {
  type    = list(string)
  default = ["alice", "bob", "carol"]
}

variable "base_tags" {
  type = map(string)
  default = {
    Project = "iac-demo"
    Owner   = "platform"
  }
}

variable "extra_tags" {
  type = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

locals {
  user_set = toset(var.user_list)

  user_policy_arns = {
    alice = [
      "arn:aws:iam::aws:policy/AmazonS3FullAccess",
      "arn:aws:iam::aws:policy/IAMReadOnlyAccess",
    ]
    bob = [
      "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
    ]
    carol = [
      "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess",
      "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess",
    ]
  }

  user_tags = {
    for name in var.user_list :
    name => merge(
      var.base_tags,
      var.extra_tags,
      {
        Name = name
        Role = lookup({
          alice = "admin"
          bob   = "developer"
          carol = "analyst"
        }, name, "user")
      }
    )
  }

  bucket_names = {
    for name in var.user_list :
    name => lower(join("-", [name, "data", "bucket"]))
  }

  policy_pairs = flatten([
    for user_name, arns in local.user_policy_arns : [
      for arn in arns : {
        user_name = user_name
        arn       = arn
        key       = "${user_name}-${replace(replace(arn, "arn:aws:iam::aws:policy/", ""), "/", "-")}"
      }
    ]
  ])

  policy_map = {
    for pair in local.policy_pairs :
    pair.key => pair
  }
}

resource "aws_iam_user" "users" {
  for_each = local.user_set

  name = each.value
  tags = local.user_tags[each.value]
}

resource "aws_iam_user_policy_attachment" "attachments" {
  for_each = local.policy_map

  user       = aws_iam_user.users[each.value.user_name].name
  policy_arn = each.value.arn
}

resource "aws_s3_bucket" "user_buckets" {
  for_each = local.user_set

  bucket = local.bucket_names[each.value]
  tags   = local.user_tags[each.value]
}

output "user_names" {
  value = [for u in aws_iam_user.users : u.name]
}

output "bucket_names" {
  value = [for b in aws_s3_bucket.user_buckets : b.bucket]
}

output "attached_policies" {
  value = {
    for k, v in aws_iam_user_policy_attachment.attachments :
    k => {
      user       = v.user
      policy_arn = v.policy_arn
    }
  }
}