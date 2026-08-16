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

resource "aws_s3_bucket" "input" {
  bucket        = "${var.name_prefix}-input-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-input"
  }
}

resource "aws_sqs_queue" "processing" {
  name                       = "${var.name_prefix}-processing-queue"
  visibility_timeout_seconds = 60
}

resource "aws_dynamodb_table" "results" {
  name         = "${var.name_prefix}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S"
  }

  tags = {
    Name = "${var.name_prefix}-results"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.name_prefix}-lambda-exec"

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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.processing.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.results.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.input.arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.name_prefix}-processor"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda_function_payload.zip"
  source_code_hash  = filebase64sha256("lambda_function_payload.zip")
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      INPUT_BUCKET   = aws_s3_bucket.input.bucket
      QUEUE_URL      = aws_sqs_queue.processing.url
      RESULTS_TABLE  = aws_dynamodb_table.results.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-lambda-alerts"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  alarm_description   = "Monitors Lambda error count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

variable "name_prefix" {
  type    = string
  default = "serverless-pipeline"
}