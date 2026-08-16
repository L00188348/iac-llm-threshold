variable "topic_name" {
  type        = string
  default     = "my-topic.fifo"
  description = "Name of the SNS FIFO topic."

  validation {
    condition     = endswith(var.topic_name, ".fifo")
    error_message = "topic_name must end with .fifo"
  }
}

resource "aws_sns_topic" "fifo_topic" {
  name                        = var.topic_name
  fifo_topic                  = true
  content_based_deduplication = true
}

resource "aws_sqs_queue" "standard_queue" {
  name = "standard-queue"
}

resource "aws_sns_topic_subscription" "queue_subscription" {
  topic_arn            = aws_sns_topic.fifo_topic.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.standard_queue.arn
  raw_message_delivery = true
}