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

resource "aws_s3_bucket" "this" {
  bucket = "example-bucket-dynamic-principals"
}

data "aws_iam_policy_document" "bucket_policy" {
  count = length(var.principals)

  statement {
    sid    = "Principal${count.index}"
    effect = "Allow"

    actions   = var.principals[count.index].permissions
    resources = [
      "${aws_s3_bucket.this.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [var.principals[count.index].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [for doc in data.aws_iam_policy_document.bucket_policy : jsondecode(doc.json).Statement[0]]
  })
}