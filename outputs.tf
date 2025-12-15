output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms"
  value       = aws_sns_topic.ec2_monitoring_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.ec2_monitoring_alerts.name
}

output "email_subscription_status" {
  description = "Status of email subscription (check your email to confirm)"
  value       = aws_sns_topic_subscription.ec2_monitoring_email.id
}

output "alarm_names" {
  description = "Names of all created CloudWatch alarms"
  value = {
    disk_usage_alarms    = { for k, v in aws_cloudwatch_metric_alarm.disk_usage : k => v.alarm_name }
    memory_usage_alarms   = { for k, v in aws_cloudwatch_metric_alarm.memory_usage : k => v.alarm_name }
    cpu_utilization_alarms = { for k, v in aws_cloudwatch_metric_alarm.cpu_utilization : k => v.alarm_name }
  }
}

