terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "alarms" {
  type = map(object({
    metric_name       = string
    statistic         = string
    threshold         = number
    evaluation_periods = number
    alarm_actions     = list(string)
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

resource "aws_sns_topic" "alarms" {
  name = "cloudwatch-alarms-topic"
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = var.alarms

  alarm_name          = each.key
  comparison_operator  = "GreaterThanThreshold"
  evaluation_periods   = each.value.evaluation_periods
  threshold           = each.value.threshold
  alarm_actions       = length(each.value.alarm_actions) > 0 ? each.value.alarm_actions : [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  metric_name         = each.value.metric_name
  namespace           = "AWS/EC2"
  statistic           = each.value.statistic
}

output "alarm_arns" {
  value = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.arn }
}