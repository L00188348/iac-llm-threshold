terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "bucket_name" {
  type    = string
  default = null
}

variable "table_name" {
  type    = string
  default = "example-dynamodb-table"
}

variable "lambda_function_name" {
  type    = string
  default = "example-multi-resource-lambda"
}

variable "api_name" {
  type    = string
  default = "example-http-api"
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = coalesce(var.bucket_name, "example-app-bucket-${random_id.suffix.hex}")

  lifecycle {
    ignore_changes = [
      tags,
      force_destroy,
    ]
  }
}

resource "aws_s3_bucket_versioning" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "app_table" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  lifecycle {
    ignore_changes = [
      stream_enabled,
      point_in_time_recovery,
    ]
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "example-lambda-role-${random_id.suffix.hex}"

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
  name = "example-lambda-policy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_role.id

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
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_bucket.arn,
          "${aws_s3_bucket.app_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.app_table.arn
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "app" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.app_bucket.bucket
      TABLE_NAME  = aws_dynamodb_table.app_table.name
      TABLE_ARN   = aws_dynamodb_table.app_table.arn
      BUCKET_ARN   = aws_s3_bucket.app_bucket.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_s3_bucket_versioning.app_bucket,
  ]

  lifecycle {
    ignore_changes = [
      memory_size,
      timeout,
      environment[0].variables,
    ]
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = var.api_name
  protocol_type = "HTTP"

  lifecycle {
    ignore_changes = [
      description,
      route_selection_expression,
    ]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  lifecycle {
    ignore_changes = [
      deployment_id,
    ]
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "random_id" "suffix" {
  byte_length = 4
}

output "bucket_name" {
  value = aws_s3_bucket.app_bucket.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.app_bucket.arn
}

output "table_name" {
  value = aws_dynamodb_table.app_table.name
}

output "table_arn" {
  value = aws_dynamodb_table.app_table.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.app.arn
}

output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}