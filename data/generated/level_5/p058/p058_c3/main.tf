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

locals {
  lambda_functions = {
    python_function = {
      runtime       = "python3.12"
      handler       = "lambda_function.lambda_handler"
      timeout       = 30
      memory_size   = 128
      permissions   = ["logs", "s3"]
      description   = "Python Lambda function"
    }
    node_function = {
      runtime       = "nodejs20.x"
      handler       = "index.handler"
      timeout       = 15
      memory_size   = 256
      permissions   = ["logs", "dynamodb"]
      description   = "Node.js Lambda function"
    }
  }

  permission_actions = {
    logs = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    s3 = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    dynamodb = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
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

resource "aws_iam_role" "lambda" {
  for_each           = local.lambda_functions
  name               = "${each.key}-role"
  assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  for_each = local.lambda_functions

  dynamic "statement" {
    for_each = toset(each.value.permissions)
    content {
      effect    = "Allow"
      actions   = local.permission_actions[statement.value]
      resources = ["*"]
    }
  }
}

resource "aws_iam_policy" "lambda" {
  for_each = local.lambda_functions
  name     = "${each.key}-policy"
  policy   = data.aws_iam_policy_document.lambda_permissions[each.key].json
}

resource "aws_iam_role_policy_attachment" "lambda" {
  for_each = local.lambda_functions

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = aws_iam_policy.lambda[each.key].arn
}

resource "aws_lambda_function" "this" {
  for_each = local.lambda_functions

  function_name    = each.key
  role             = aws_iam_role.lambda[each.key].arn
  handler          = each.value.handler
  runtime          = each.value.runtime
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = each.value.timeout
  memory_size      = each.value.memory_size
  description      = each.value.description

  depends_on = [aws_iam_role_policy_attachment.lambda]
}

output "lambda_function_arns" {
  value = { for k, f in aws_lambda_function.this : k => f.arn }
}