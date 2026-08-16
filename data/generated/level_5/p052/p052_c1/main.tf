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
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy into."
}

variable "name_prefix" {
  type        = string
  default     = "event-driven"
  description = "Prefix used for naming resources."
}

variable "s3_bucket_name" {
  type        = string
  default     = null
  description = "Optional explicit S3 bucket name. If null, a unique name is generated."
}

variable "object_prefix" {
  type        = string
  default     = ""
  description = "Optional key prefix filter for S3 object creation notifications."
}

variable "image_queue_retention_seconds" {
  type        = number
  default     = 345600
  description = "Message retention period for the image queue in seconds."
}

variable "video_queue_retention_seconds" {
  type        = number
  default     = 345600
  description = "Message retention period for the video queue in seconds."
}

variable "dlq_retention_seconds" {
  type        = number
  default     = 1209600
  description = "Message retention period for all dead-letter queues in seconds."
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "source" {
  bucket = var.s3_bucket_name != null ? var.s3_bucket_name : "${var.name_prefix}-${data.aws_caller_identity.current.account_id}-source"
}

resource "aws_sns_topic" "events" {
  name = "${var.name_prefix}-events"
}

resource "aws_sqs_queue" "image_dlq" {
  name                       = "${var.name_prefix}-image-dlq"
  message_retention_seconds  = var.dlq_retention_seconds
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue" "video_dlq" {
  name                       = "${var.name_prefix}-video-dlq"
  message_retention_seconds  = var.dlq_retention_seconds
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue" "image_queue" {
  name                       = "${var.name_prefix}-image-queue"
  message_retention_seconds  = var.image_queue_retention_seconds
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "video_queue" {
  name                       = "${var.name_prefix}-video-queue"
  message_retention_seconds  = var.video_queue_retention_seconds
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "sns_to_sqs_image" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.image_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.events.arn]
    }
  }
}

data "aws_iam_policy_document" "sns_to_sqs_video" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.video_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "image" {
  queue_url = aws_sqs_queue.image_queue.id
  policy    = data.aws_iam_policy_document.sns_to_sqs_image.json
}

resource "aws_sqs_queue_policy" "video" {
  queue_url = aws_sqs_queue.video_queue.id
  policy    = data.aws_iam_policy_document.sns_to_sqs_video.json
}

resource "aws_sns_topic_subscription" "image" {
  topic_arn             = aws_sns_topic.events.arn
  protocol              = "sqs"
  endpoint              = aws_sqs_queue.image_queue.arn
  raw_message_delivery  = false

  filter_policy = jsonencode({
    file_type = ["image"]
  })
}

resource "aws_sns_topic_subscription" "video" {
  topic_arn             = aws_sns_topic.events.arn
  protocol              = "sqs"
  endpoint              = aws_sqs_queue.video_queue.arn
  raw_message_delivery  = false

  filter_policy = jsonencode({
    file_type = ["video"]
  })
}

data "aws_iam_policy_document" "s3_publish_to_sns" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.events.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source.arn]
    }
  }
}

resource "aws_sns_topic_policy" "events" {
  arn    = aws_sns_topic.events.arn
  policy = data.aws_iam_policy_document.s3_publish_to_sns.json
}

resource "aws_s3_bucket_notification" "source" {
  bucket = aws_s3_bucket.source.id

  topic {
    topic_arn     = aws_sns_topic.events.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.object_prefix
  }

  depends_on = [aws_sns_topic_policy.events]
}