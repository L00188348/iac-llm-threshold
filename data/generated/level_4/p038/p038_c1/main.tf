variable "alarms" {
  type = map(object({
    metric_name        = string
    statistic          = string
    threshold          = number
    evaluation_periods = number
    alarm_actions      = list(string)
  }))

  default = {
    high_cpu = {
      metric_name        = "CPUUtilization"
      statistic          = "Average"
      threshold          = 80
      evaluation_periods = 2
      alarm_actions      = []
    }
  }

  validation {
    condition = alltrue([
      for _, alarm in var.alarms : alarm.threshold > 0 && alarm.evaluation_periods >= 1
    ])
    error_message = "Each alarm must have threshold > 0 and evaluation_periods >= 1."
  }
}

resource "aws_sns_topic" "alarm_actions" {
  name = "cloudwatch-alarm-actions"
}

locals {
  alarms_with_actions = {
    for name, alarm in var.alarms : name => merge(alarm, {
      alarm_actions = length(alarm.alarm_actions) > 0 ? alarm.alarm_actions : [aws_sns_topic.alarm_actions.arn]
    })
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms_with_actions

  alarm_name          = each.key
  metric_name         = each.value.metric_name
  namespace           = "AWS/EC2"
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = each.value.alarm_actions
}

output "alarm_arns" {
  value = { for name, alarm in aws_cloudwatch_metric_alarm.this : name => alarm.arn }
}