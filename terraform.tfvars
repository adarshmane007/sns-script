environment            = "dev"
cloudwatch_alarm_email = "adarshmane007@gmail.com"

# Multi-instance configuration - Production ready
# Add multiple instances here, each will be monitored independently
instances = [
  {
    name      = "redis-server-1"
    tag_key   = "Name"
    tag_value = "sns tag testing "
    device    = "nvme0n1p1"
  },
  {
    name      = "target-instance"
    tag_key   = "Name"
    tag_value = "Target"
    device    = "nvme0n1p1"
  }
]

# Legacy single-instance support (deprecated - use instances list above instead)
# instance_tag_key       = "Name"
# instance_tag_value     = "sns tag testing "
# instance_name          = "monitored-instance"
# device_name            = "nvme0n1p1"

