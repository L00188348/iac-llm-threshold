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

resource "aws_s3_bucket" "input" {
  bucket = var.workflow_config.input_bucket
}

resource "aws_s3_bucket" "output" {
  bucket = var.workflow_config.output_bucket
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.workflow_config.queue_name}-dlq"
}

resource "aws_sqs_queue" "processing" {
  name = var.workflow_config.queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.workflow_config.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_sqs_s3" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [aws_sqs_queue.processing.arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }

  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.output.arn}/*"]
  }
}

resource "aws_iam_role_policy" "lambda_sqs_s3" {
  name   = "${var.workflow_config.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_sqs_s3.json
}

resource "aws_lambda_function" "processor" {
  function_name    = var.workflow_config.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
  enabled          = true
}

output "queue_url" {
  value = aws_sqs_queue.processing.url
}

output "lambda_arn" {
  value = aws_lambda_function.processor.arn
}