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
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "event-arch"
}

variable "s3_bucket_name" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {
    Project = "event-driven-architecture"
  }
}

locals {
  bucket_name = coalesce(var.s3_bucket_name, "${var.name_prefix}-source-${random_id.bucket_suffix.hex}")

  queues = {
    image = {
      retention_seconds   = 345600
      visibility_timeout   = 60
      dlq_retention_days   = 14
      filter_value         = "image"
    }
    video = {
      retention_seconds   = 1209600
      visibility_timeout   = 120
      dlq_retention_days   = 14
      filter_value         = "video"
    }
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "source" {
  bucket = local.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_notification" "source" {
  bucket = aws_s3_bucket.source.id

  topic {
    topic_arn     = aws_sns_topic.object_created.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
  }

  depends_on = [aws_sns_topic_policy.allow_s3_publish]
}

resource "aws_sns_topic" "object_created" {
  name = "${var.name_prefix}-object-created"
  tags = var.tags
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "sns_allow_s3_publish" {
  statement {
    sid     = "AllowS3Publish"
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    resources = [aws_sns_topic.object_created.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "allow_s3_publish" {
  arn    = aws_sns_topic.object_created.arn
  policy = data.aws_iam_policy_document.sns_allow_s3_publish.json
}

resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name                      = "${var.name_prefix}-${each.key}-dlq"
  message_retention_seconds = each.value.dlq_retention_days * 24 * 60 * 60
  tags                      = var.tags
}

resource "aws_sqs_queue" "main" {
  for_each = local.queues

  name                       = "${var.name_prefix}-${each.key}"
  message_retention_seconds   = each.value.retention_seconds
  visibility_timeout_seconds  = each.value.visibility_timeout
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 5
  })
  tags = var.tags
}

data "aws_iam_policy_document" "sqs_allow_sns" {
  for_each = local.queues

  statement {
    sid     = "AllowSNSTopicSendMessage"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.main[each.key].arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.object_created.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "main" {
  for_each = local.queues

  queue_url = aws_sqs_queue.main[each.key].id
  policy    = data.aws_iam_policy_document.sqs_allow_sns[each.key].json
}

resource "aws_sns_topic_subscription" "main" {
  for_each = local.queues

  topic_arn = aws_sns_topic.object_created.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.main[each.key].arn

  filter_policy = jsonencode({
    file_type = [each.value.filter_value]
  })

  raw_message_delivery = true
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.source.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.object_created.arn
}

output "sqs_queue_arns" {
  value = { for k, v in aws_sqs_queue.main : k => v.arn }
}