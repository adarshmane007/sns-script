# SNS Topic for EC2 monitoring alerts

resource "aws_sns_topic" "ec2_monitoring_alerts" {
  name         = "ec2-monitoring-alerts"
  display_name = "EC2 Monitoring Alerts"

  tags = {
    Name        = "ec2-monitoring-alerts"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "ec2_monitoring_email" {
  topic_arn = aws_sns_topic.ec2_monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.cloudwatch_alarm_email
}

