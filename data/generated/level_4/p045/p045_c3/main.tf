variable "subscription_config" {
  type = object({
    topic_name = string
    queues = map(object({
      filter_policy = string
    }))
  })

  default = {
    topic_name = "test-topic"
    queues = {
      high = {
        filter_policy = "{\"priority\":[\"high\"]}"
      }
      low = {
        filter_policy = "{\"priority\":[\"low\"]}"
      }
    }
  }
}

resource "aws_sns_topic" "this" {
  name = var.subscription_config.topic_name
}

resource "aws_sqs_queue" "this" {
  for_each = var.subscription_config.queues

  name = "${var.subscription_config.topic_name}-${each.key}"
}

resource "aws_sns_topic_subscription" "this" {
  for_each = var.subscription_config.queues

  topic_arn = aws_sns_topic.this.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.this[each.key].arn

  filter_policy = each.value.filter_policy
}

output "queue_arns" {
  value = { for k, q in aws_sqs_queue.this : k => q.arn }
}