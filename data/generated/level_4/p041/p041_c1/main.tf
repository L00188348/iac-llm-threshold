variable "backup_config" {
  type = object({
    table_name                    = string
    backup_retention_days         = number
    enable_point_in_time_recovery  = bool
  })

  default = {
    table_name                   = "backup-table"
    backup_retention_days        = 7
    enable_point_in_time_recovery = true
  }

  validation {
    condition     = var.backup_config.backup_retention_days >= 1 && var.backup_config.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

resource "aws_dynamodb_table" "backup_table" {
  name         = var.backup_config.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.backup_config.enable_point_in_time_recovery
  }

  tags = {
    backup_retention_days = tostring(var.backup_config.backup_retention_days)
  }
}

output "table_arn" {
  value = aws_dynamodb_table.backup_table.arn
}