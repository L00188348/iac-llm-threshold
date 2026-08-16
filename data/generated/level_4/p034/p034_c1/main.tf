variable "workflow_config" {
  type = object({
    input_bucket  = string
    output_bucket = string
    queue_name    = string
    function_name = string
  })

  default = {
    input_bucket  = "input-bucket"
    output_bucket = "output-bucket"
    queue_name    = "processing-queue"
    function_name = "processor"
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "input" {
  bucket = var.workflow_config.input_bucket
}

resource "aws_s3_bucket" "output" {
  bucket = var.workflow_config.output_bucket
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.workflow_config.queue_name}-dlq"
}

resource "aws_sqs_queue" "main" {
  name = var.workflow_config.queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_iam_role" "lambda" {
  name = "${var.workflow_config.function_name}-role"

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
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_sqs" {
  name = "${var.workflow_config.function_name}-s3-sqs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  function_name    = var.workflow_config.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      INPUT_BUCKET  = aws_s3_bucket.input.bucket
      OUTPUT_BUCKET = aws_s3_bucket.output.bucket
      QUEUE_URL     = aws_sqs_queue.main.url
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
  enabled          = true
}

output "queue_url" {
  value = aws_sqs_queue.main.url
}

output "lambda_arn" {
  value = aws_lambda_function.processor.arn
}