terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

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

resource "aws_apigatewayv2_api" "this" {
  name          = var.api_config.api_name
  protocol_type = "HTTP"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.api_config.api_name}-lambda-role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name = var.api_config.api_name
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs20.x"
  handler       = var.api_config.routes[0].handler
  memory_size   = var.api_config.memory_size
  timeout       = var.api_config.timeout

  filename         = "lambda_function_payload.zip"
  source_code_hash  = filebase64sha256("lambda_function_payload.zip")
  publish           = true

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

resource "aws_apigatewayv2_integration" "this" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = {
    for route in var.api_config.routes : "${route.method} ${route.path}" => route
  }

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "${upper(each.value.method)} ${each.value.path}"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.this.api_endpoint
}