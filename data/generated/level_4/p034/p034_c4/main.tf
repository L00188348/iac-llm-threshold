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

resource "aws_iam_role" "lambda_exec" {
  name = "${var.workflow_config.function_name}-exec-role"

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

resource "aws_lambda_function" "processor" {
  function_name = var.workflow_config.function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.processor.arn
  enabled          = true
  batch_size       = 10
}

resource "aws_s3_bucket_notification" "input_to_sqs" {
  bucket = aws_s3_bucket.input.id

  queue {
    queue_arn     = aws_sqs_queue.processing.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "allow_s3_to_sqs" {
  statement {
    sid    = "AllowS3ToSendMessage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sqs:SendMessage"]

    resources = [aws_sqs_queue.processing.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.input.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.processing.id
  policy    = data.aws_iam_policy_document.allow_s3_to_sqs.json
}

output "queue_url" {
  value = aws_sqs_queue.processing.url
}

output "lambda_arn" {
  value = aws_lambda_function.processor.arn
}