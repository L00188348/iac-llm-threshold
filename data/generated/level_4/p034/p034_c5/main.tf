variable "workflow_config" {
  type = object({
    input_bucket   = string
    output_bucket  = string
    queue_name     = string
    function_name  = string
  })

  default = {
    input_bucket   = "input-bucket"
    output_bucket  = "output-bucket"
    queue_name     = "processing-queue"
    function_name  = "processor"
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
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.workflow_config.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*",
      aws_s3_bucket.output.arn,
      "${aws_s3_bucket.output.arn}/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]

    resources = [aws_sqs_queue.processing.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${var.workflow_config.function_name}-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "processor" {
  function_name    = var.workflow_config.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      INPUT_BUCKET  = aws_s3_bucket.input.bucket
      OUTPUT_BUCKET  = aws_s3_bucket.output.bucket
      QUEUE_URL      = aws_sqs_queue.processing.id
      QUEUE_ARN      = aws_sqs_queue.processing.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.processor.arn
  enabled          = true
  batch_size       = 10
}

output "queue_url" {
  value = aws_sqs_queue.processing.id
}

output "lambda_arn" {
  value = aws_lambda_function.processor.arn
}