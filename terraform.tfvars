environment            = "dev"
cloudwatch_alarm_email = "adarshmane007@gmail.com"

# Multi-instance configuration - Production ready
# Add multiple instances here, each will be monitored independently
instances = [
  {
    name      = "test-instance"
    tag_key   = "Name"
    tag_value = "test"
    device    = "nvme0n1p1"
  },
  {
    name      = "final-sns"
    tag_key   = "Name"
    tag_value = "final-sns"
    device    = "nvme0n1p1"
  },
  {
    name      = "alaram"
    tag_key   = "Name"
    tag_value = "alaram"
    device    = "nvme0n1p1"
  },
  {
    name      = "final"
    tag_key   = "Name"
    tag_value = "final"
    device    = "nvme0n1p1"
  },
  {
    name      = "last"
    tag_key   = "Name"
    tag_value = "last"
    device    = "nvme0n1p1"
  },
  {
    name      = "deploy"
    tag_key   = "Name"
    tag_value = "Deploy"
    device    = "nvme0n1p1"
  }

]

# Legacy single-instance support (deprecated - use instances list above instead)
# instance_tag_key       = "Name"
# instance_tag_value     = "sns tag testing "
# instance_name          = "monitored-instance"
# device_name            = "nvme0n1p1"

