# Multi-instance support: Find instances by tags or instance_id
# Supports both legacy single-instance mode and new multi-instance mode

# Determine which mode to use: new instances list or legacy variables
locals {
  # Use new instances list if provided, otherwise fall back to legacy single instance
  instances_to_monitor = length(var.instances) > 0 ? var.instances : (
    var.instance_id != "" || (var.instance_tag_key != "" && var.instance_tag_value != "") ? [
      {
        name        = var.instance_name
        tag_key     = var.instance_tag_key
        tag_value   = var.instance_tag_value
        instance_id = var.instance_id
        device      = var.device_name
      }
    ] : []
  )
}

# Data sources to find instances by tags (one per instance config)
data "aws_instances" "tagged_instances" {
  for_each = {
    for idx, inst in local.instances_to_monitor : inst.name => inst
    if inst.instance_id == "" && inst.tag_key != "" && inst.tag_value != ""
  }

  filter {
    name   = "tag:${each.value.tag_key}"
    values = [each.value.tag_value]
  }

  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

# Local to resolve instance IDs (from direct ID or tags)
locals {
  resolved_instance_ids = {
    for idx, inst in local.instances_to_monitor : inst.name => (
      inst.instance_id != "" ? inst.instance_id : (
        # Check if this instance has tags and was found
        inst.tag_key != "" && inst.tag_value != "" && contains(keys(data.aws_instances.tagged_instances), inst.name) && length(data.aws_instances.tagged_instances[inst.name].ids) > 0 ? data.aws_instances.tagged_instances[inst.name].ids[0] : ""
      )
    )
  }
}

# Local to store device mapping
locals {
  instance_devices = {
    for idx, inst in local.instances_to_monitor : inst.name => inst.device
  }
}

# Fetch instance details for each instance
data "aws_instance" "instances" {
  for_each = {
    for name, instance_id in local.resolved_instance_ids : name => instance_id
    if instance_id != ""
  }

  instance_id = each.value
}

# Create instances map for use in resources
locals {
  ec2_instances_map = {
    for name, instance_data in data.aws_instance.instances : name => {
      instance_id   = instance_data.id
      name          = name
      device        = lookup(local.instance_devices, name, "nvme0n1p1")
      ami           = instance_data.ami
      instance_type = instance_data.instance_type
    }
  }

  # Backward compatibility: single instance references
  monitored_instance_id   = length(local.ec2_instances_map) > 0 ? values(local.ec2_instances_map)[0].instance_id : ""
  monitored_instance_ami  = length(local.ec2_instances_map) > 0 ? values(local.ec2_instances_map)[0].ami : ""
  monitored_instance_type = length(local.ec2_instances_map) > 0 ? values(local.ec2_instances_map)[0].instance_type : ""

  # Validation: Check if all configured instances were found
  missing_instances = [
    for inst in local.instances_to_monitor : inst.name
    if !contains(keys(local.ec2_instances_map), inst.name)
  ]
}

