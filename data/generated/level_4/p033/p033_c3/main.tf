variable "api_config" {
  type = object({
    api_name    = string
    routes      = list(object({ path = string, method = string, handler = string }))
    memory_size = number
    timeout     = number
  })
  default = {
    api_name = "test-api"
    routes = [
      {
        path    = "/hello"
        method  = "GET"
        handler = "index.handler"
      }
    ]
    memory_size = 128
    timeout     = 3
  }

  validation {
    condition     = var.api_config.memory_size >= 128 && var.api_config.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240."
  }

  validation {
    condition     = var.api_config.timeout >= 3 && var.api_config.timeout <= 900
    error_message = "timeout must be between 3 and 900 seconds."
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  routes = {
    for route in var.api_config.routes :
    "${upper(route.method)} ${route.path}" => route
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.api_config.api_name}-lambda-exec"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_apigatewayv2_api" "this" {
  name          = var.api_config.api_name
  protocol_type = "HTTP"
}

resource "aws_lambda_function" "this" {
  function_name = "${var.api_config.api_name}-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = try(var.api_config.routes[0].handler, "index.handler")
  runtime       = "nodejs20.x"
  memory_size   = var.api_config.memory_size
  timeout       = var.api_config.timeout

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "${upper(each.value.method)} ${each.value.path}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.this.api_endpoint
}