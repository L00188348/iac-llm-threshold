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

resource "aws_s3_bucket" "app" {
  bucket_prefix = "multi-resource-orchestration-"

  tags = {
    Name        = "app-bucket"
    Environment = "demo"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_dynamodb_table" "app" {
  name         = "multi-resource-orchestration-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "app-table"
    Environment = "demo"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "multi-resource-orchestration-lambda-exec"

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

resource "aws_iam_role_policy" "lambda_access" {
  name = "multi-resource-orchestration-lambda-access"
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
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
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
        Resource = aws_dynamodb_table.app.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "app" {
  function_name = "multi-resource-orchestration-function"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.app.bucket
      TABLE_NAME  = aws_dynamodb_table.app.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_access
  ]

  lifecycle {
    ignore_changes = [
      environment[0].variables
    ]
  }
}

resource "aws_apigatewayv2_api" "app" {
  name          = "multi-resource-orchestration-api"
  protocol_type = "HTTP"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.app.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.app.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.app.id
  name        = "$default"
  auto_deploy = true

  lifecycle {
    ignore_changes = [deployment_id]
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGatewayV2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app.execution_arn}/*/*"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.app.name
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.app.api_endpoint
}