variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cloudwatch_alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = "adarshmane007@gmail.com"
}

variable "instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}

variable "instance_name" {
  description = "Name identifier for the EC2 instance"
  type        = string
  default     = "monitored-instance"
}

variable "device_name" {
  description = "Device name for disk metrics (e.g., nvme0n1p1, xvda, sda1)"
  type        = string
  default     = "nvme0n1p1"
}

