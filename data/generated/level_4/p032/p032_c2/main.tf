variable "db_config" {
  type = object({
    table_name     = string
    hash_key       = string
    sort_key       = string
    billing_mode   = string
    read_capacity  = number
    write_capacity = number
  })

  default = {
    table_name     = "test-table"
    hash_key       = "UserId"
    sort_key       = "Timestamp"
    billing_mode   = "PAY_PER_REQUEST"
    read_capacity  = 0
    write_capacity = 0
  }

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.db_config.billing_mode)
    error_message = "billing_mode must be either \"PROVISIONED\" or \"PAY_PER_REQUEST\"."
  }

  validation {
    condition = var.db_config.billing_mode != "PROVISIONED" || (
      var.db_config.read_capacity >= 1 && var.db_config.write_capacity >= 1
    )
    error_message = "When billing_mode is \"PROVISIONED\", read_capacity and write_capacity must both be >= 1."
  }
}

resource "aws_dynamodb_table" "db" {
  name         = var.db_config.table_name
  billing_mode = var.db_config.billing_mode
  hash_key     = var.db_config.hash_key
  range_key    = var.db_config.sort_key

  attribute {
    name = var.db_config.hash_key
    type = "S"
  }

  attribute {
    name = var.db_config.sort_key
    type = "S"
  }

  read_capacity  = var.db_config.billing_mode == "PROVISIONED" ? var.db_config.read_capacity : null
  write_capacity = var.db_config.billing_mode == "PROVISIONED" ? var.db_config.write_capacity : null
}

output "table_arn" {
  value = aws_dynamodb_table.db.arn
}