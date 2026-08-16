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
  bucket = "${var.bucket_prefix}-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_sqs_queue" "pipeline" {
  name = "${var.queue_name_prefix}-${random_id.suffix.hex}"
}

resource "aws_dynamodb_table" "results" {
  name         = "${var.table_name_prefix}-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_role_name_prefix}-${random_id.suffix.hex}"

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
  name = "${var.lambda_policy_name_prefix}-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
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
  function_name    = "${var.lambda_name_prefix}-${random_id.suffix.hex}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      INPUT_BUCKET   = aws_s3_bucket.input.bucket
      QUEUE_URL      = aws_sqs_queue.pipeline.url
      RESULTS_TABLE   = aws_dynamodb_table.results.name
      RESULTS_TABLE_ARN = aws_dynamodb_table.results.arn
      INPUT_BUCKET_ARN  = aws_s3_bucket.input.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.pipeline.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_sns_topic" "lambda_alerts" {
  name = "${var.sns_topic_name_prefix}-${random_id.suffix.hex}"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.lambda_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.alarm_name_prefix}-${random_id.suffix.hex}"
  alarm_description   = "Alarm when Lambda errors exceed threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 300
  statistic           = "Sum"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.lambda_alerts.arn]
  ok_actions    = [aws_sns_topic.lambda_alerts.arn]
}

variable "bucket_prefix" {
  type    = string
  default = "serverless-input-bucket"
}

variable "queue_name_prefix" {
  type    = string
  default = "serverless-pipeline-queue"
}

variable "table_name_prefix" {
  type    = string
  default = "serverless-results-table"
}

variable "lambda_role_name_prefix" {
  type    = string
  default = "serverless-lambda-role"
}

variable "lambda_policy_name_prefix" {
  type    = string
  default = "serverless-lambda-policy"
}

variable "lambda_name_prefix" {
  type    = string
  default = "serverless-processor"
}

variable "sns_topic_name_prefix" {
  type    = string
  default = "serverless-lambda-alerts"
}

variable "alarm_name_prefix" {
  type    = string
  default = "serverless-lambda-errors"
}

variable "alert_email" {
  type = string
}