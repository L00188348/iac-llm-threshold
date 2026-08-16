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

variable "project_name" {
  type    = string
  default = "iac-demo"
}

resource "aws_s3_bucket" "data" {
  bucket = "${var.project_name}-data-bucket"

  tags = {
    Name = "${var.project_name}-data-bucket"
    ManagedBy = "Terraform"
  }

  lifecycle {
    ignore_changes = [
      tags["ManagedBy"],
    ]
  }
}

resource "aws_dynamodb_table" "state" {
  name         = "${var.project_name}-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-state"
    ManagedBy = "Terraform"
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_access" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]

    resources = [
      aws_dynamodb_table.state.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_access" {
  name   = "${var.project_name}-lambda-access"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_access.json
}

resource "aws_lambda_function" "processor" {
  function_name    = "${var.project_name}-processor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.data.bucket
      TABLE_NAME  = aws_dynamodb_table.state.name
      TABLE_ARN   = aws_dynamodb_table.state.arn
      BUCKET_ARN  = aws_s3_bucket.data.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_access,
  ]

  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
      environment[0].variables["BUCKET_ARN"],
    ]
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-http-api"
  protocol_type = "HTTP"

  lifecycle {
    ignore_changes = [
      description,
    ]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.processor.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "invoke_lambda" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  lifecycle {
    ignore_changes = [
      default_route_settings,
    ]
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowInvokeFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.state.name
}

output "lambda_function_name" {
  value = aws_lambda_function.processor.function_name
}

output "api_gateway_endpoint" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

output "api_gateway_id" {
  value = aws_apigatewayv2_api.http.id
}