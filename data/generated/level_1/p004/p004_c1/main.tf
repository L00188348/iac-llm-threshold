variable "queue_name" {
  type    = string
  default = "test-queue"
}

variable "message_retention_seconds" {
  type    = number
  default = 1209600
}

variable "delay_seconds" {
  type    = number
  default = 5
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = var.message_retention_seconds
}

resource "aws_sqs_queue" "main" {
  name                      = var.queue_name
  delay_seconds             = var.delay_seconds
  message_retention_seconds = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}