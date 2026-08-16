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
    sid     = "AllowRootAccountAdmin"
    effect  = "Allow"
    actions = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:root"]
    }
  }

  statement {
    sid     = "AllowSpecifiedRoleUseOnly"
    effect  = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
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
  description             = "Symmetric key for application use"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  is_enabled              = true
  policy                  = data.aws_iam_policy_document.kms_key.json
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
}

resource "aws_kms_alias" "app" {
  name          = "alias/${var.key_alias}"
  target_key_id  = aws_kms_key.app.key_id
}