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

resource "aws_s3_bucket" "input" {
  bucket = "${var.aws_region}-serverless-input-bucket-${random_string.suffix.result}"
}

resource "aws_sqs_queue" "pipeline" {
  name = "${var.aws_region}-serverless-pipeline-queue-${random_string.suffix.result}"
}

resource "aws_dynamodb_table" "results" {
  name         = "${var.aws_region}-serverless-results-${random_string.suffix.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${var.aws_region}-serverless-lambda-role-${random_string.suffix.result}"

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

resource "aws_iam_role_policy" "lambda" {
  name = "${var.aws_region}-serverless-lambda-policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.pipeline.arn
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.aws_region}-serverless-processor-${random_string.suffix.result}"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda_function_payload.zip"
  source_code_hash  = filebase64sha256("lambda_function_payload.zip")
  timeout           = 30
  memory_size       = 128
  environment {
    variables = {
      INPUT_BUCKET   = aws_s3_bucket.input.bucket
      QUEUE_URL      = aws_sqs_queue.pipeline.url
      RESULTS_TABLE   = aws_dynamodb_table.results.name
      RESULTS_TABLE_ARN = aws_dynamodb_table.results.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.pipeline.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_sns_topic" "alerts" {
  name = "${var.aws_region}-serverless-lambda-alerts-${random_string.suffix.result}"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.aws_region}-serverless-lambda-errors-${random_string.suffix.result}"
  alarm_description   = "Alarm when Lambda errors occur"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}