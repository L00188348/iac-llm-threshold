variable "log_group_name" {
  type    = string
  default = "/aws/test"
}

variable "retention_days" {
  type    = number
  default = 90
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.retention_days
}

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "error-count"
  log_group_name  = aws_cloudwatch_log_group.this.name
  pattern        = "\"ERROR\""

  metric_transformation {
    name      = "ErrorCount"
    namespace = "Custom/LogMetrics"
    value     = "1"
  }
}

resource "aws_sns_topic" "alarm" {
  name = "log-error-alarm-topic"
}

resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  alarm_name          = "log-error-count-alarm"
  alarm_description   = "Triggers when ERROR appears in logs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  namespace           = aws_cloudwatch_log_metric_filter.error_count.metric_transformation[0].namespace
  metric_name         = aws_cloudwatch_log_metric_filter.error_count.metric_transformation[0].name
  treat_missing_data  = "notBreaching"

  alarm_actions = [
    aws_sns_topic.alarm.arn
  ]
}