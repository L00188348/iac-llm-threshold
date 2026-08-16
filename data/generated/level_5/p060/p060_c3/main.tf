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

resource "aws_s3_bucket" "app_data" {
  bucket_prefix = "iac-demo-app-data-"

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "app_state" {
  name         = "iac-demo-app-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  lifecycle {
    ignore_changes = [
      read_capacity,
      write_capacity,
      tags,
    ]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "iac-demo-lambda-exec-role"

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

resource "aws_iam_role_policy" "lambda_access" {
  name = "iac-demo-lambda-access-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_data.arn,
          "${aws_s3_bucket.app_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.app_state.arn
        ]
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

resource "aws_lambda_function" "app_handler" {
  function_name = "iac-demo-app-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda_function_payload.zip"
  source_code_hash  = filebase64sha256("lambda_function_payload.zip")
  timeout           = 30
  memory_size       = 128
  publish           = true

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.app_data.bucket
      TABLE_NAME  = aws_dynamodb_table.app_state.name
    }
  }

  lifecycle {
    ignore_changes = [
      environment[0].variables,
      description,
    ]
  }

  depends_on = [
    aws_iam_role_policy.lambda_access,
    aws_s3_bucket_versioning.app_data
  ]
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "iac-demo-http-api"
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
  integration_uri        = aws_lambda_function.app_handler.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds    = 30000
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  lifecycle {
    ignore_changes = [
      default_route_settings,
      access_log_settings,
    ]
  }

  depends_on = [
    aws_apigatewayv2_route.default_route,
    aws_lambda_permission.api_gateway_invoke
  ]
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_data.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.app_state.name
}

output "lambda_function_name" {
  value = aws_lambda_function.app_handler.function_name
}

output "api_gateway_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}