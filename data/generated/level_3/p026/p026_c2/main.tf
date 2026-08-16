variable "policy_statements" {
  type = list(object({
    actions   = list(string)
    resources = list(string)
    effect    = string
  }))

  default = [
    {
      actions   = ["s3:GetObject"]
      resources = ["*"]
      effect    = "Allow"
    },
    {
      actions   = ["s3:PutObject"]
      resources = ["*"]
      effect    = "Allow"
    },
    {
      actions   = ["ec2:DescribeInstances"]
      resources = ["*"]
      effect    = "Allow"
    }
  ]
}

data "aws_iam_policy_document" "dynamic" {
  dynamic "statement" {
    for_each = var.policy_statements

    content {
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_policy" "dynamic" {
  name   = "dynamic-policy"
  policy = data.aws_iam_policy_document.dynamic.json
}