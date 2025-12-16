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
    disk_usage_alarms      = { for k, v in aws_cloudwatch_metric_alarm.disk_usage : k => v.alarm_name }
    memory_usage_alarms    = { for k, v in aws_cloudwatch_metric_alarm.memory_usage : k => v.alarm_name }
    cpu_utilization_alarms = { for k, v in aws_cloudwatch_metric_alarm.cpu_utilization : k => v.alarm_name }
  }
}

output "cloudwatch_agent_config_parameters" {
  description = "SSM Parameter names for CloudWatch Agent configuration (per instance)"
  value       = { for k, v in aws_ssm_parameter.cloudwatch_agent_config : k => v.name }
}

output "cloudwatch_agent_installation_status" {
  description = "CloudWatch Agent installation status (per instance)"
  value       = { for k, v in null_resource.install_cloudwatch_agent : k => "Installation initiated for ${k}" }
}

output "iam_role_arn" {
  description = "ARN of the shared IAM role for all EC2 instances"
  value       = aws_iam_role.ec2_cloudwatch_role.arn
}

output "iam_instance_profiles" {
  description = "IAM instance profiles attached to EC2 instances (per instance)"
  value       = { for k, v in aws_iam_instance_profile.ec2_cloudwatch_profile : k => v.name }
}

output "monitored_instances" {
  description = "List of all monitored instances with their details"
  value = {
    for k, v in local.ec2_instances_map : k => {
      instance_id   = v.instance_id
      name          = v.name
      device        = v.device
      ami           = v.ami
      instance_type = v.instance_type
    }
  }
}

output "cloudwatch_agent_status" {
  description = "CloudWatch Agent installation and configuration status"
  value       = "Installed and configured for all instances. Check target servers with: sudo systemctl status amazon-cloudwatch-agent"
}

