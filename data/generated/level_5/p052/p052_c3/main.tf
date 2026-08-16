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

variable "name_prefix" {
  type    = string
  default = "event-arch"
}

variable "bucket_name" {
  type    = string
  default = ""
}

variable "image_file_types" {
  type    = list(string)
  default = ["jpg", "jpeg", "png", "gif", "webp"]
}

variable "video_file_types" {
  type    = list(string)
  default = ["mp4", "mov", "avi", "mkv", "webm"]
}

variable "s3_object_prefix" {
  type    = string
  default = ""
}

variable "queue_message_retention_seconds" {
  type    = number
  default = 1209600
}

variable "dlq_message_retention_seconds" {
  type    = number
  default = 1209600
}

variable "max_receive_count" {
  type    = number
  default = 5
}

resource "aws_sns_topic" "events" {
  name = "${var.name_prefix}-events"
}

resource "aws_sqs_queue" "image_dlq" {
  name                        = "${var.name_prefix}-image-dlq"
  message_retention_seconds   = var.dlq_message_retention_seconds
  visibility_timeout_seconds   = 30
  receive_wait_time_seconds    = 20
  sqs_managed_sse_enabled      = true
}

resource "aws_sqs_queue" "video_dlq" {
  name                        = "${var.name_prefix}-video-dlq"
  message_retention_seconds   = var.dlq_message_retention_seconds
  visibility_timeout_seconds   = 30
  receive_wait_time_seconds    = 20
  sqs_managed_sse_enabled      = true
}

resource "aws_sqs_queue" "image_queue" {
  name                        = "${var.name_prefix}-image-queue"
  message_retention_seconds   = var.queue_message_retention_seconds
  visibility_timeout_seconds   = 30
  receive_wait_time_seconds    = 20
  sqs_managed_sse_enabled      = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue" "video_queue" {
  name                        = "${var.name_prefix}-video-queue"
  message_retention_seconds   = var.queue_message_retention_seconds
  visibility_timeout_seconds   = 30
  receive_wait_time_seconds    = 20
  sqs_managed_sse_enabled      = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

data "aws_iam_policy_document" "image_queue_policy" {
  statement {
    sid     = "AllowSNSPublish"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.image_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.events.arn]
    }
  }
}

data "aws_iam_policy_document" "video_queue_policy" {
  statement {
    sid     = "AllowSNSPublish"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.video_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "image_queue" {
  queue_url = aws_sqs_queue.image_queue.id
  policy    = data.aws_iam_policy_document.image_queue_policy.json
}

resource "aws_sqs_queue_policy" "video_queue" {
  queue_url = aws_sqs_queue.video_queue.id
  policy    = data.aws_iam_policy_document.video_queue_policy.json
}

resource "aws_sns_topic_subscription" "image_queue" {
  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.image_queue.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    file_type = var.image_file_types
  })
}

resource "aws_sns_topic_subscription" "video_queue" {
  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.video_queue.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    file_type = var.video_file_types
  })
}

data "aws_iam_policy_document" "s3_to_sns" {
  statement {
    sid    = "AllowS3PublishToSNS"
    effect = "Allow"

    actions = ["sns:Publish"]

    resources = [aws_sns_topic.events.arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "events" {
  arn    = aws_sns_topic.events.arn
  policy = data.aws_iam_policy_document.s3_to_sns.json
}

resource "aws_s3_bucket" "source" {
  bucket = var.bucket_name != "" ? var.bucket_name : "${var.name_prefix}-${random_id.bucket_suffix.hex}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_notification" "source" {
  bucket = aws_s3_bucket.source.id

  topic {
    topic_arn = aws_sns_topic.events.arn
    events    = ["s3:ObjectCreated:*"]
    filter_prefix = var.s3_object_prefix != "" ? var.s3_object_prefix : null
  }

  depends_on = [aws_sns_topic_policy.events]
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}