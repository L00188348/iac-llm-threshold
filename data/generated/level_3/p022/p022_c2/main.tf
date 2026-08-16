variable "queue_settings" {
  type = list(object({
    name      = string
    retention = number
    delay     = number
  }))

  default = [
    {
      name      = "dev"
      retention = 259200
      delay     = 0
    },
    {
      name      = "staging"
      retention = 604800
      delay     = 5
    },
    {
      name      = "prod"
      retention = 1209600
      delay     = 10
    }
  ]
}

resource "aws_sqs_queue" "this" {
  count = length(var.queue_settings)

  name                       = var.queue_settings[count.index].name
  message_retention_seconds  = var.queue_settings[count.index].retention
  delay_seconds              = var.queue_settings[count.index].delay
}