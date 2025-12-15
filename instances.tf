# Data source to fetch existing EC2 instance information
# This allows you to monitor an existing instance by ID

data "aws_instance" "monitored_instance" {
  instance_id = var.instance_id
}

# Local value to create the instances map dynamically
locals {
  ec2_instances_map = {
    monitored = {
      instance_id = var.instance_id
      name        = var.instance_name
      device      = var.device_name
    }
  }
}

