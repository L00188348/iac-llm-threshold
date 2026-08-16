variable "table_name" {
  type    = string
  default = "test-table"
}

variable "table_attributes" {
  type = list(object({
    name = string
    type = string
  }))
  default = [
    {
      name = "UserId"
      type = "S"
    },
    {
      name = "Timestamp"
      type = "S"
    },
    {
      name = "GSIKey"
      type = "S"
    }
  ]
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "Timestamp"

  dynamic "attribute" {
    for_each = var.table_attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  global_secondary_index {
    name            = "gsi-by-key"
    hash_key        = "GSIKey"
    projection_type  = "ALL"
  }
}