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
  log_group_name = aws_cloudwatch_log_group.this.name
  pattern        = "\"ERROR\""

  metric_transformation {
    name      = "ErrorCount"
    namespace = "Custom/LogMetrics"
    value     = "1"
  }
}

resource "aws_sns_topic" "this" {
  name = "log-error-alerts"
}

resource "aws_cloudwatch_metric_alarm" "error_count_alarm" {
  alarm_name          = "log-error-count-alarm"
  alarm_description   = "Triggers when ERROR occurrences are detected in the log group"
  namespace           = aws_cloudwatch_log_metric_filter.error_count.metric_transformation[0].namespace
  metric_name         = aws_cloudwatch_log_metric_filter.error_count.metric_transformation[0].name
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.this.arn]
}