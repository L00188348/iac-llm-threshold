terraform {
  required_version = ">= 1.3.0"

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
    stream_name            = string
    shard_count            = number
    retention_hours        = number
    consumer_function_name  = string
  })

  default = {
    stream_name           = "test-stream"
    shard_count           = 1
    retention_hours       = 24
    consumer_function_name = "consumer"
  }
}

locals {
  message_retention_seconds = min(max(var.stream_config.retention_hours * 3600, 60), 1209600)
}

resource "aws_sqs_queue" "stream_queue" {
  name                      = var.stream_config.stream_name
  message_retention_seconds = local.message_retention_seconds
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
  function_name    = var.stream_config.consumer_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_event_source_mapping" "queue_to_lambda" {
  event_source_arn = aws_sqs_queue.stream_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  enabled          = true
  batch_size       = 10
}

output "queue_url" {
  value = aws_sqs_queue.stream_queue.url
}

output "lambda_arn" {
  value = aws_lambda_function.consumer.arn
}