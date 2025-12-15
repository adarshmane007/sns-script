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

output "cloudwatch_agent_config_parameter" {
  description = "SSM Parameter name for CloudWatch Agent configuration"
  value       = aws_ssm_parameter.cloudwatch_agent_config.name
}

output "cloudwatch_agent_ssm_association_id" {
  description = "SSM Association ID for CloudWatch Agent installation"
  value       = aws_ssm_association.cloudwatch_agent.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to EC2 instance"
  value       = aws_iam_role.ec2_cloudwatch_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile attached to EC2 instance"
  value       = aws_iam_instance_profile.ec2_cloudwatch_profile.name
}

