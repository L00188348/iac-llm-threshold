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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_sns_topic" "alerts" {
  name = "serverless-pipeline-alerts"
}

resource "aws_s3_bucket" "input" {
  bucket = "serverless-pipeline-input-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_sqs_queue" "queue" {
  name = "serverless-pipeline-queue"
}

resource "aws_dynamodb_table" "results" {
  name         = "serverless-pipeline-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda" {
  name = "serverless-pipeline-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "serverless-pipeline-lambda-policy"
  role = aws_iam_role.lambda.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.results.arn
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  function_name    = "serverless-pipeline-processor"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = 30

  environment {
    variables = {
      INPUT_BUCKET    = aws_s3_bucket.input.bucket
      QUEUE_URL       = aws_sqs_queue.queue.url
      RESULTS_TABLE   = aws_dynamodb_table.results.name
      AWS_REGION      = data.aws_region.current.name
      ACCOUNT_ID      = data.aws_caller_identity.current.account_id
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda
  ]
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.queue.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "serverless-pipeline-lambda-errors"
  alarm_description   = "Alarm when Lambda error count is greater than zero"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  statistic           = "Sum"
  period              = 300
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}