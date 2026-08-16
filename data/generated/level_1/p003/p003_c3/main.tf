variable "table_name" {
  type    = string
  default = "test-table"
}

variable "hash_key" {
  type    = string
  default = "UserId"
}

variable "sort_key" {
  type    = string
  default = "Timestamp"
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key
  range_key    = var.sort_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  attribute {
    name = var.sort_key
    type = "S"
  }

  ttl {
    attribute_name = "ExpireAt"
    enabled        = true
  }
}