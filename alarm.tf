# CloudWatch Alarms for all EC2 instances
# Creates alarms for disk usage, memory usage, and CPU utilization
# The instances map is defined in instances.tf

# Disk Usage Alarm (> 80%)
# IMPORTANT: Device name varies by instance type:
#   - NVMe instances: nvme0n1p1, nvme1n1p1, etc.
#   - Xen instances: xvda, xvdb, etc.
#   - SATA instances: sda1, sdb1, etc.
# To find the actual device name for your instance:
#   1. Run: aws cloudwatch list-metrics --namespace CWAgent --metric-name disk_used_percent --region ap-south-1
#   2. Look for the device dimension value for your InstanceId
#   3. Update the 'device' field in ec2_instances_map above
resource "aws_cloudwatch_metric_alarm" "disk_usage" {
  for_each = local.ec2_instances_map

  alarm_name          = "${each.value.name}-disk-usage-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors disk usage for ${each.value.name}"
  alarm_actions       = [aws_sns_topic.ec2_monitoring_alerts.arn]

  # CloudWatch Agent sends disk metrics with InstanceId, path, device, fstype, ImageId, and InstanceType dimensions
  # All dimensions must match exactly for the alarm to work
  # Using data source to get ImageId and InstanceType dynamically
  dimensions = {
    InstanceId   = each.value.instance_id
    path         = "/"
    device       = try(each.value.device, "nvme0n1p1") # Default to nvme0n1p1 if not specified
    fstype       = "xfs"                               # File system type - adjust if your instance uses a different filesystem
    ImageId      = each.value.ami
    InstanceType = each.value.instance_type
  }

  tags = {
    Name        = "${each.value.name}-disk-usage-alarm"
    Environment = var.environment
    Instance    = each.value.name
  }
}

# Memory Usage Alarm (> 80%)
resource "aws_cloudwatch_metric_alarm" "memory_usage" {
  for_each = local.ec2_instances_map

  alarm_name          = "${each.value.name}-memory-usage-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors memory usage for ${each.value.name}"
  alarm_actions       = [aws_sns_topic.ec2_monitoring_alerts.arn]

  # CloudWatch Agent sends memory metrics with InstanceId, ImageId, and InstanceType dimensions
  # All dimensions must match exactly for the alarm to work
  # Using data source to get ImageId and InstanceType dynamically
  dimensions = {
    InstanceId   = each.value.instance_id
    ImageId      = each.value.ami
    InstanceType = each.value.instance_type
  }

  tags = {
    Name        = "${each.value.name}-memory-usage-alarm"
    Environment = var.environment
    Instance    = each.value.name
  }
}

# CPU Utilization Alarm (> 90%)
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  for_each = local.ec2_instances_map

  alarm_name          = "${each.value.name}-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "This metric monitors CPU utilization for ${each.value.name}"
  alarm_actions       = [aws_sns_topic.ec2_monitoring_alerts.arn]

  dimensions = {
    InstanceId = each.value.instance_id
  }

  tags = {
    Name        = "${each.value.name}-cpu-utilization-alarm"
    Environment = var.environment
    Instance    = each.value.name
  }
}

