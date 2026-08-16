variable "env_vars" {
  type = map(string)
  default = {
    ENV       = "prod"
    LOG_LEVEL = "info"
    REGION    = "us-east-1"
  }
}

variable "lambda_functions" {
  type = map(object({
    handler = string
    runtime  = string
    role_arn = string
  }))
  default = {
    example = {
      handler = "index.handler"
      runtime  = "nodejs20.x"
      role_arn = "arn:aws:iam::123456789012:role/lambda-execution-role"
    }
  }
}

resource "aws_lambda_function" "this" {
  for_each = var.lambda_functions

  function_name = each.key
  role          = each.value.role_arn
  handler       = each.value.handler
  runtime       = each.value.runtime
  filename      = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = { for k, v in var.env_vars : k => v }
  }
}