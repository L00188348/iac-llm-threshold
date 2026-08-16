variable "key_alias" {
  type    = string
  default = "app-key"
}

variable "key_usage_iam_role" {
  type    = string
  default = "arn:aws:iam::000000000000:role/app-role"
}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:root"]
    }

    actions = [
      "kms:*",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    sid    = "AllowSpecifiedRoleKeyUsage"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.key_usage_iam_role]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [
      "*",
    ]
  }
}

resource "aws_kms_key" "app" {
  description             = "KMS symmetric key for application usage"
  deletion_window_in_days  = 30
  enable_key_rotation     = true
  enabled                 = true
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  policy                  = data.aws_iam_policy_document.kms_key_policy.json
}

resource "aws_kms_alias" "app" {
  name          = "alias/${var.key_alias}"
  target_key_id  = aws_kms_key.app.key_id
}