variable "bucket_name" {
  type    = string
  default = "test-bucket"
}

variable "queue_name" {
  type    = string
  default = "test-queue"
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}

resource "aws_sqs_queue" "this" {
  name = var.queue_name
}

data "aws_iam_policy_document" "sqs" {
  statement {
    sid     = "AllowS3BucketToSendMessages"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    resources = [aws_sqs_queue.this.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.this.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.sqs.json
}

resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  queue {
    queue_arn     = aws_sqs_queue.this.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
  }

  depends_on = [aws_sqs_queue_policy.this]
}