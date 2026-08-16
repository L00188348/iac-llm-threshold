terraform {
  required_version = ">= 1.5.0"

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
    stream_name               = string
    shard_count               = number
    retention_hours           = number
    consumer_function_name    = string
  })

  default = {
    stream_name            = "test-stream"
    shard_count            = 1
    retention_hours        = 24
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

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.stream_config.consumer_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "dummy_lambda_zip" {
  type        = "zip"
  source_file = "lambda_function_payload.zip"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "consumer" {
  function_name    = var.stream_config.consumer_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_lambda_event_source_mapping" "sqs_mapping" {
  event_source_arn = aws_sqs_queue.stream_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 10
  enabled          = true
}

output "queue_url" {
  value = aws_sqs_queue.stream_queue.id
}

output "lambda_arn" {
  value = aws_lambda_function.consumer.arn
}