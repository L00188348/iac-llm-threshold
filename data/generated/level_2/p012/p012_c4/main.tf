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

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSToSendMessage"
        Effect    = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.this.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.this.arn
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.this.arn
}