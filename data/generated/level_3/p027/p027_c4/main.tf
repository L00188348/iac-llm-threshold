variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0"
}

variable "threshold" {
  type    = number
  default = 80
}

variable "evaluation_periods" {
  type    = number
  default = 2
}

variable "period" {
  type    = number
  default = 300
}

resource "aws_sns_topic" "alarm_topic" {
  name = "ec2-cpu-alarm-topic"
}

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "ec2-cpu-utilization-alarm"
  alarm_description   = "Triggers when EC2 CPUUtilization exceeds the threshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.threshold
  evaluation_periods  = var.evaluation_periods
  period              = var.period
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
  dimensions = {
    InstanceId = aws_instance.this.id
  }
}