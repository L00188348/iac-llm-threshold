variable "principals" {
  type = list(object({
    arn         = string
    permissions = list(string)
  }))

  default = [
    {
      arn         = "arn:aws:iam::000000000000:role/role1"
      permissions = ["s3:GetObject"]
    },
    {
      arn         = "arn:aws:iam::000000000000:role/role2"
      permissions = ["s3:PutObject"]
    }
  ]
}

variable "bucket_name" {
  type    = string
  default = "example-bucket"
}

data "aws_iam_policy_document" "bucket" {
  count = length(var.principals)

  statement {
    sid    = "Principal${count.index}"
    effect = "Allow"

    actions = var.principals[count.index].permissions

    principals {
      type        = "AWS"
      identifiers = [var.principals[count.index].arn]
    }

    resources = [
      "arn:aws:s3:::${var.bucket_name}/*"
    ]
  }
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [for doc in data.aws_iam_policy_document.bucket : doc.statement[0]]
  })
}