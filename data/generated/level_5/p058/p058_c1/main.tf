variable "lambda_functions" {
  type = map(object({
    runtime     = string
    handler     = string
    description = string
    permissions = list(string)
  }))

  default = {
    python_example = {
      runtime     = "python3.11"
      handler     = "lambda_function.lambda_handler"
      description = "Python Lambda function"
      permissions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    }
    node_example = {
      runtime     = "nodejs20.x"
      handler     = "index.handler"
      description = "Node.js Lambda function"
      permissions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "assume_role" {
  for_each = var.lambda_functions

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

  name               = "${each.key}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json
}

data "aws_iam_policy_document" "lambda_permissions" {
  for_each = var.lambda_functions

  statement {
    effect    = "Allow"
    actions   = each.value.permissions
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda" {
  for_each = var.lambda_functions

  name   = "${each.key}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_permissions[each.key].json
}

resource "aws_iam_role_policy_attachment" "lambda" {
  for_each = var.lambda_functions

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = aws_iam_policy.lambda[each.key].arn
}

resource "aws_lambda_function" "lambda" {
  for_each = var.lambda_functions

  function_name = each.key
  role          = aws_iam_role.lambda[each.key].arn
  runtime       = each.value.runtime
  handler       = each.value.handler
  description   = each.value.description

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  depends_on = [aws_iam_role_policy_attachment.lambda]
}

output "lambda_function_arns" {
  value = { for k, v in aws_lambda_function.lambda : k => v.arn }
}