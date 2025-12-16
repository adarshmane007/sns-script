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

# Legacy single instance support (backward compatible)
variable "instance_id" {
  description = "EC2 instance ID to monitor (optional if using tags) - DEPRECATED: Use instances list instead"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Name identifier for the EC2 instance - DEPRECATED: Use instances list instead"
  type        = string
  default     = "monitored-instance"
}

variable "instance_tag_key" {
  description = "Tag key to identify EC2 instances (e.g., 'Name') - DEPRECATED: Use instances list instead"
  type        = string
  default     = ""
}

variable "instance_tag_value" {
  description = "Tag value to identify EC2 instances (e.g., 'sns tag testing') - DEPRECATED: Use instances list instead"
  type        = string
  default     = ""
}

variable "device_name" {
  description = "Device name for disk metrics (e.g., nvme0n1p1, xvda, sda1) - DEPRECATED: Use instances list instead"
  type        = string
  default     = "nvme0n1p1"
}

# Multi-instance support - Production ready
variable "instances" {
  description = "List of EC2 instances to monitor. Each instance can be identified by tag or instance_id"
  type = list(object({
    name        = string                    # Unique name identifier for this instance
    tag_key     = optional(string, "")      # Tag key to find instance (e.g., "Name")
    tag_value   = optional(string, "")      # Tag value to find instance (e.g., "redis-server-1")
    instance_id = optional(string, "")      # Direct instance ID (alternative to tags)
    device      = optional(string, "nvme0n1p1") # Device name for disk metrics
  }))
  default = []
}

