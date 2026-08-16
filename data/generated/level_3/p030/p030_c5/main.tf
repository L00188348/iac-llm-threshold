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

resource "aws_s3_bucket" "example" {
  bucket = "example-bucket-dynamic-principals"
}

data "aws_iam_policy_document" "bucket" {
  count = length(var.principals)

  statement {
    sid    = "Statement${count.index}"
    effect = "Allow"

    actions = var.principals[count.index].permissions

    principals {
      type        = "AWS"
      identifiers = [var.principals[count.index].arn]
    }

    resources = [
      "${aws_s3_bucket.example.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.example.id
  policy = data.aws_iam_policy_document.bucket[0].json
}