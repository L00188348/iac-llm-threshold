variable "key_alias" {
  type    = string
  default = "app-key"
}

variable "key_usage_iam_role" {
  type    = string
  default = "arn:aws:iam::000000000000:role/app-role"
}

data "aws_iam_policy_document" "kms_key" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowSpecifiedRoleUsage"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.key_usage_iam_role]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "Symmetric key for application use"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation     = true
  is_enabled              = true
  policy                  = data.aws_iam_policy_document.kms_key.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.key_alias}"
  target_key_id  = aws_kms_key.this.key_id
}