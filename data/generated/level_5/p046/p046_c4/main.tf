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
  bucket = "${var.bucket_name_prefix}-input-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_sqs_queue" "pipeline" {
  name                       = "${var.queue_name_prefix}-pipeline"
  visibility_timeout_seconds = 60
}

resource "aws_dynamodb_table" "results" {
  name         = "${var.table_name_prefix}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.role_name_prefix}-lambda-exec"

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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.role_name_prefix}-lambda-policy"
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
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  function_name    = "${var.lambda_name_prefix}-processor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = 60

  environment {
    variables = {
      QUEUE_URL        = aws_sqs_queue.pipeline.url
      RESULTS_TABLE    = aws_dynamodb_table.results.name
      INPUT_BUCKET     = aws_s3_bucket.input.bucket
      INPUT_BUCKET_ARN = aws_s3_bucket.input.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda_policy]
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.pipeline.arn
  function_name    = aws_lambda_function.processor.arn
  enabled          = true
  batch_size       = 10
}

resource "aws_sns_topic" "alarms" {
  name = "${var.topic_name_prefix}-lambda-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.lambda_name_prefix}-error-count"
  alarm_description   = "Alarm when Lambda errors occur"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  statistic           = "Sum"
  period              = 300
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

variable "bucket_name_prefix" {
  type    = string
  default = "serverless"
}

variable "queue_name_prefix" {
  type    = string
  default = "serverless"
}

variable "table_name_prefix" {
  type    = string
  default = "serverless"
}

variable "role_name_prefix" {
  type    = string
  default = "serverless"
}

variable "lambda_name_prefix" {
  type    = string
  default = "serverless"
}

variable "topic_name_prefix" {
  type    = string
  default = "serverless"
}

variable "alarm_email" {
  type    = string
  default = ""
}