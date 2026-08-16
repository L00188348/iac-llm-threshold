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

variable "lambda_functions" {
  type = map(object({
    runtime            = string
    handler            = string
    policy_actions     = list(string)
    policy_resources    = list(string)
    timeout            = optional(number, 10)
    memory_size        = optional(number, 128)
  }))

  default = {
    python_function = {
      runtime         = "python3.11"
      handler         = "app.lambda_handler"
      policy_actions  = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      policy_resources = ["*"]
      timeout         = 15
      memory_size     = 128
    }
    node_function = {
      runtime         = "nodejs20.x"
      handler         = "index.handler"
      policy_actions  = ["s3:ListBucket", "s3:GetObject"]
      policy_resources = ["*"]
      timeout         = 20
      memory_size     = 256
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  for_each           = var.lambda_functions
  name               = "${each.key}-role"
  assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  for_each = var.lambda_functions

  statement {
    effect    = "Allow"
    actions   = each.value.policy_actions
    resources = each.value.policy_resources
  }
}

resource "aws_iam_policy" "lambda" {
  for_each = var.lambda_functions
  name     = "${each.key}-policy"
  policy   = data.aws_iam_policy_document.lambda_permissions[each.key].json
}

resource "aws_iam_role_policy_attachment" "lambda" {
  for_each   = var.lambda_functions
  role       = aws_iam_role.lambda[each.key].name
  policy_arn = aws_iam_policy.lambda[each.key].arn
}

resource "aws_lambda_function" "this" {
  for_each = var.lambda_functions

  function_name    = each.key
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = each.value.runtime
  handler          = each.value.handler
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  timeout          = each.value.timeout
  memory_size      = each.value.memory_size

  depends_on = [aws_iam_role_policy_attachment.lambda]
}

output "lambda_function_arns" {
  value = {
    for k, v in aws_lambda_function.this : k => v.arn
  }
}