terraform {
  required_version = ">= 1.0.0"
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
}

variable "message_retention_seconds" {
  type    = number
  default = 86400

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600."
  }
}

resource "aws_sqs_queue" "stream_queue" {
  name                      = var.stream_config.stream_name
  message_retention_seconds = var.message_retention_seconds
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stream_config.consumer_function_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "consumer" {
  function_name    = var.stream_config.consumer_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.stream_queue.id
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.stream_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 10
  enabled          = true
}

output "queue_url" {
  value = aws_sqs_queue.stream_queue.url
}

output "lambda_arn" {
  value = aws_lambda_function.consumer.arn
}