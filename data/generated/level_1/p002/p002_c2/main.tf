variable "key_alias" {
  type    = string
  default = "app-key"
}

variable "key_usage_iam_role" {
  type    = string
  default = "arn:aws:iam::000000000000:role/app-role"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowSpecifiedRoleUse"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.key_usage_iam_role]
    }
  }
}

resource "aws_kms_key" "app" {
  description             = "KMS symmetric key for application use"
  deletion_window_in_days  = 7
  enable_key_rotation      = true
  is_enabled              = true
  policy                 = data.aws_iam_policy_document.kms_key_policy.json
}

resource "aws_kms_alias" "app" {
  name          = "alias/${var.key_alias}"
  target_key_id  = aws_kms_key.app.key_id
}