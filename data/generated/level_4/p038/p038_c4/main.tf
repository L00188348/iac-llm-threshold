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
      for alarm in values(var.alarms) : alarm.threshold > 0 && alarm.evaluation_periods >= 1
    ])
    error_message = "Each alarm must have threshold > 0 and evaluation_periods >= 1."
  }
}

resource "aws_sns_topic" "alarm_actions" {
  name = "cloudwatch-alarm-actions"
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = var.alarms

  alarm_name          = each.key
  comparison_operator = "GreaterThanThreshold"
  metric_name         = each.value.metric_name
  namespace           = "AWS/EC2"
  statistic          = each.value.statistic
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  alarm_actions       = length(each.value.alarm_actions) > 0 ? each.value.alarm_actions : [aws_sns_topic.alarm_actions.arn]
}

output "alarm_arns" {
  value = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.arn }
}