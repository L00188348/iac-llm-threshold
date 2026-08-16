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
    python_example = {
      function_name   = "python-example"
      handler         = "app.lambda_handler"
      runtime         = "python3.11"
      permissions     = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      policy_actions  = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      policy_resources = ["arn:aws:logs:*:*:*"]
    }
    node_example = {
      function_name   = "node-example"
      handler         = "index.handler"
      runtime         = "nodejs20.x"
      permissions     = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      policy_actions  = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      policy_resources = ["arn:aws:logs:*:*:*"]
    }
  }
}

data "aws_iam_policy_document" "assume_role" {
  for_each = local.lambda_functions

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
  for_each = local.lambda_functions

  name               = "${each.value.function_name}-role"
  assume_role_policy  = data.aws_iam_policy_document.assume_role[each.key].json
}

data "aws_iam_policy_document" "lambda_permissions" {
  for_each = local.lambda_functions

  statement {
    effect    = "Allow"
    actions   = each.value.policy_actions
    resources = each.value.policy_resources
  }
}

resource "aws_iam_role_policy" "lambda" {
  for_each = local.lambda_functions

  name   = "${each.value.function_name}-policy"
  role   = aws_iam_role.lambda[each.key].id
  policy = data.aws_iam_policy_document.lambda_permissions[each.key].json
}

resource "aws_lambda_function" "this" {
  for_each = local.lambda_functions

  function_name    = each.value.function_name
  role             = aws_iam_role.lambda[each.key].arn
  handler          = each.value.handler
  runtime          = each.value.runtime
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = 30
  memory_size      = 128

  depends_on = [aws_iam_role_policy.lambda]
}

output "lambda_function_arns" {
  value = { for k, v in aws_lambda_function.this : k => v.arn }
}