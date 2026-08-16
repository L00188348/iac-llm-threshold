variable "topic_name" {
  type    = string
  default = "test-topic"
}

resource "aws_sns_topic" "this" {
  name = var.topic_name
}

resource "aws_sqs_queue" "this" {
  name = "${var.topic_name}-queue"
}

data "aws_iam_policy_document" "sqs_queue_policy" {
  statement {
    sid     = "AllowSNSToSendMessage"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    resources = [
      aws_sqs_queue.this.arn
    ]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = [
        aws_sns_topic.this.arn
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.this.arn
}