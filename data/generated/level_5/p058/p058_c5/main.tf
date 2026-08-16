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
    runtime = string
    handler = string
    timeout = optional(number, 3)
    memory_size = optional(number, 128)
    permissions = list(object({
      actions   = list(string)
      resources = list(string)
    }))
  }))

  default = {
    python_example = {
      runtime = "python3.12"
      handler = "app.lambda_handler"
      timeout = 10
      memory_size = 256
      permissions = [
        {
          actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
          resources = ["*"]
        }
      ]
    }

    node_example = {
      runtime = "nodejs20.x"
      handler = "index.handler"
      timeout = 10
      memory_size = 256
      permissions = [
        {
          actions   = ["s3:ListBucket"]
          resources = ["*"]
        }
      ]
    }
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
  for_each = var.lambda_functions

  name               = "${each.key}-role"
  assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  for_each = var.lambda_functions

  dynamic "statement" {
    for_each = { for idx, perm in each.value.permissions : idx => perm }
    content {
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  for_each = var.lambda_functions

  name   = "${each.key}-policy"
  role   = aws_iam_role.lambda[each.key].id
  policy = data.aws_iam_policy_document.lambda_permissions[each.key].json
}

resource "aws_lambda_function" "this" {
  for_each = var.lambda_functions

  function_name = each.key
  role          = aws_iam_role.lambda[each.key].arn
  runtime       = each.value.runtime
  handler       = each.value.handler
  timeout       = each.value.timeout
  memory_size   = each.value.memory_size

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

output "lambda_function_arns" {
  value = { for k, f in aws_lambda_function.this : k => f.arn }
}