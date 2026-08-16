variable "topic_name" {
  type    = string
  default = "my-topic.fifo"

  validation {
    condition     = can(regex("\\.fifo$", var.topic_name))
    error_message = "topic_name must end with .fifo."
  }
}

resource "aws_sns_topic" "this" {
  name                        = var.topic_name
  fifo_topic                  = true
  content_based_deduplication = true
}

resource "aws_sqs_queue" "this" {
  name = "my-queue"
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn            = aws_sns_topic.this.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this.arn
  raw_message_delivery = true
}