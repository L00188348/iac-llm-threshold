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
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "event-driven"
}

variable "s3_bucket_name" {
  description = "Optional explicit S3 bucket name. If null, a unique name is generated."
  type        = string
  default     = null
}

variable "queue_message_retention_seconds" {
  description = "Message retention period for the primary queues."
  type        = number
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  description = "Message retention period for dead-letter queues."
  type        = number
  default     = 1209600
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for the primary queues."
  type        = number
  default     = 30
}

variable "sqs_delay_seconds" {
  description = "Default delay seconds for primary queues."
  type        = number
  default     = 0
}

variable "s3_events" {
  description = "S3 event types to send to SNS."
  type        = list(string)
  default     = ["s3:ObjectCreated:*"]
}

variable "notifications_enabled" {
  description = "Whether to enable bucket notifications."
  type        = bool
  default     = true
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  bucket        = coalesce(var.s3_bucket_name, "${var.name_prefix}-${random_id.suffix.hex}")
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-bucket"
  }
}

resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  topic {
    topic_arn     = aws_sns_topic.s3_events.arn
    events        = var.s3_events
    filter_prefix = ""
    filter_suffix = ""
  }

  depends_on = [aws_sns_topic_policy.allow_s3_publish]
}

resource "aws_sns_topic" "s3_events" {
  name = "${var.name_prefix}-s3-events"
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowS3Publish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.s3_events.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.this.arn]
    }
  }
}

resource "aws_sns_topic_policy" "allow_s3_publish" {
  arn    = aws_sns_topic.s3_events.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_subscription" "sqs_image" {
  topic_arn            = aws_sns_topic.s3_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.image.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    file_type = ["image"]
  })
}

resource "aws_sns_topic_subscription" "sqs_video" {
  topic_arn            = aws_sns_topic.s3_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.video.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    file_type = ["video"]
  })
}

resource "aws_sqs_queue" "image_dlq" {
  name                      = "${var.name_prefix}-image-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
}

resource "aws_sqs_queue" "video_dlq" {
  name                      = "${var.name_prefix}-video-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
}

resource "aws_sqs_queue" "image" {
  name                      = "${var.name_prefix}-image"
  message_retention_seconds = var.queue_message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  delay_seconds             = var.sqs_delay_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "video" {
  name                      = "${var.name_prefix}-video"
  message_retention_seconds = var.queue_message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  delay_seconds             = var.sqs_delay_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "sqs_queue_policy" {
  statement {
    sid    = "AllowSNSPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions   = ["SQS:SendMessage"]
    resources = [aws_sqs_queue.image.arn, aws_sqs_queue.video.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.s3_events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "image" {
  queue_url = aws_sqs_queue.image.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}

resource "aws_sqs_queue_policy" "video" {
  queue_url = aws_sqs_queue.video.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}

output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.s3_events.arn
}

output "image_queue_url" {
  value = aws_sqs_queue.image.id
}

output "video_queue_url" {
  value = aws_sqs_queue.video.id
}

output "image_dlq_url" {
  value = aws_sqs_queue.image_dlq.id
}

output "video_dlq_url" {
  value = aws_sqs_queue.video_dlq.id
}