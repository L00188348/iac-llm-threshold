terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "stream_config" {
  type = object({
    stream_name             = string
    shard_count             = number
    retention_hours         = number
    consumer_function_name  = string
  })

  default = {
    stream_name            = "test-stream"
    shard_count            = 1
    retention_hours        = 24
    consumer_function_name = "consumer"
  }

  validation {
    condition     = var.stream_config.retention_hours >= 1 && var.stream_config.retention_hours <= 14
    error_message = "stream_config.retention_hours must be between 1 and 14 hours."
  }

  validation {
    condition     = var.stream_config.shard_count >= 1
    error_message = "stream_config.shard_count must be at least 1."
  }
}

locals {
  queue_retention_seconds = var.stream_config.retention_hours * 3600
}

resource "aws_sqs_queue" "stream_queue" {
  name                      = var.stream_config.stream_name
  message_retention_seconds = local.queue_retention_seconds

  lifecycle {
    precondition {
      condition     = local.queue_retention_seconds >= 60 && local.queue_retention_seconds <= 1209600
      error_message = "message_retention_seconds must be between 60 and 1209600."
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stream_config.consumer_function_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "consumer" {
  function_name = var.stream_config.consumer_function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.stream_queue.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

output "queue_url" {
  value = aws_sqs_queue.stream_queue.id
}

output "lambda_arn" {
  value = aws_lambda_function.consumer.arn
}