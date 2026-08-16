variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type    = string
  default = "event-driven-archive-bucket"
}

variable "sns_topic_name" {
  type    = string
  default = "s3-object-created-events"
}

variable "image_queue_name" {
  type    = string
  default = "image-file-events"
}

variable "video_queue_name" {
  type    = string
  default = "video-file-events"
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}

variable "dlq_message_retention_seconds" {
  type    = number
  default = 1209600
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "sns_to_sqs" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.image_queue.arn,
      aws_sqs_queue.video_queue.arn
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.s3_events.arn]
    }
  }
}

resource "aws_s3_bucket" "events" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_notification" "events" {
  bucket = aws_s3_bucket.events.id

  topic {
    topic_arn = aws_sns_topic.s3_events.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.allow_s3_publish]
}

resource "aws_sns_topic" "s3_events" {
  name = var.sns_topic_name
}

data "aws_iam_policy_document" "allow_s3_publish" {
  statement {
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
      values   = [aws_s3_bucket.events.arn]
    }
  }
}

resource "aws_sns_topic_policy" "allow_s3_publish" {
  arn    = aws_sns_topic.s3_events.arn
  policy = data.aws_iam_policy_document.allow_s3_publish.json
}

resource "aws_sqs_queue" "image_dlq" {
  name                      = "${var.image_queue_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
}

resource "aws_sqs_queue" "video_dlq" {
  name                      = "${var.video_queue_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
}

resource "aws_sqs_queue" "image_queue" {
  name                      = var.image_queue_name
  message_retention_seconds = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "video_queue" {
  name                      = var.video_queue_name
  message_retention_seconds = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "image_queue" {
  queue_url = aws_sqs_queue.image_queue.id
  policy    = data.aws_iam_policy_document.sns_to_sqs.json
}

resource "aws_sqs_queue_policy" "video_queue" {
  queue_url = aws_sqs_queue.video_queue.id
  policy    = data.aws_iam_policy_document.sns_to_sqs.json
}

resource "aws_sns_topic_subscription" "image_subscription" {
  topic_arn = aws_sns_topic.s3_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.image_queue.arn

  filter_policy = jsonencode({
    file_type = ["image"]
  })

  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.image_queue]
}

resource "aws_sns_topic_subscription" "video_subscription" {
  topic_arn = aws_sns_topic.s3_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.video_queue.arn

  filter_policy = jsonencode({
    file_type = ["video"]
  })

  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.video_queue]
}

data "aws_iam_policy_document" "bucket_notifications" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.s3_events.arn]
  }
}