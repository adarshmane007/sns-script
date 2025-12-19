resource "aws_cloudwatch_dashboard" "ec2_monitoring_dashboard_v4" {
  dashboard_name = "EC2-Monitoring-Dashboard-v4"

  dashboard_body = jsonencode({
    version = "1.0"
    widgets = concat(
      # CPU Utilization widgets
      [
        for instance_idx, instance in values(local.ec2_instances_map) : {
          type   = "metric"
          x      = 0
          y      = instance_idx * 6
          width  = 8
          height = 6
          properties = {
            metrics = [
              ["AWS/EC2", "CPUUtilization", "InstanceId", instance.instance_id]
            ]
            view   = "gauge"
            region = var.aws_region
            title  = "${instance.name} - CPU Utilization"
            period = 300
            stat   = "Average"
            yAxis = {
              left = {
                min = 0
                max = 100
              }
            }
            annotations = {
              horizontal = [
                {
                  value   = 70
                  label   = "Good"
                  color   = "#2ca02c" # green
                  fill    = "below"
                  yAxis   = "left"
                  visible = true
                },
                {
                  value   = 70
                  label   = "Warning"
                  color   = "#ff9900" # orange
                  fill    = "above"
                  yAxis   = "left"
                  visible = true
                },
                {
                  value   = 85
                  label   = "Critical"
                  color   = "#ff0000" # red
                  fill    = "above"
                  yAxis   = "left"
                  visible = true
                }
              ]
            }
            thresholds = [
              {
                value   = 70
                color   = "#2ca02c" # green
                fill    = "below"
                yAxis   = "left"
                visible = true
                label   = "Good"
              },
              {
                value   = 70
                color   = "#ff9900" # orange
                fill    = "above"
                yAxis   = "left"
                visible = true
                label   = "Warning"
              },
              {
                value   = 85
                color   = "#ff0000" # red
                fill    = "above"
                yAxis   = "left"
                visible = true
                label   = "Critical"
              }
            ]
          }
        }
      ],
      # Memory Usage widgets
      [
        for instance_idx, instance in values(local.ec2_instances_map) : {
          type   = "metric"
          x      = 8
          y      = instance_idx * 6
          width  = 8
          height = 6
          properties = {
            metrics = [
              ["CWAgent", "mem_used_percent", "InstanceId", instance.instance_id, "ImageId", instance.ami, "InstanceType", instance.instance_type]
            ]
            view   = "gauge"
            region = var.aws_region
            title  = "${instance.name} - Memory Usage"
            period = 300
            stat   = "Average"
            yAxis = {
              left = {
                min = 0
                max = 100
              }
            }
            annotations = {
              horizontal = [
                {
                  value   = 70
                  label   = "Good"
                  color   = "#2ca02c" # green
                  fill    = "below"
                  yAxis   = "left"
                  visible = true
                },
                {
                  value   = 70
                  label   = "Warning"
                  color   = "#ff9900" # orange
                  fill    = "above"
                  yAxis   = "left"
                  visible = true
                },
                {
                  value   = 85
                  label   = "Critical"
                  color   = "#ff0000" # red
                  fill    = "above"
                  yAxis   = "left"
                  visible = true
                }
              ]
            }
            thresholds = [
              {
                value   = 70
                color   = "#2ca02c" # green
                fill    = "below"
                yAxis   = "left"
                visible = true
                label   = "Good"
              },
              {
                value   = 70
                color   = "#ff9900" # orange
                fill    = "above"
                yAxis   = "left"
                visible = true
                label   = "Warning"
              },
              {
                value   = 85
                color   = "#ff0000" # red
                fill    = "above"
                yAxis   = "left"
                visible = true
                label   = "Critical"
              }
            ]
          }
        }
      ],
      # Disk Usage widgets
      [
        for instance_idx, instance in values(local.ec2_instances_map) : {
          type   = "metric"
          x      = 16
          y      = instance_idx * 6
          width  = 8
          height = 6
          properties = {
            metrics = [
              ["CWAgent", "disk_used_percent", "InstanceId", instance.instance_id, "path", "/", "device", try(instance.device, "nvme0n1p1"), "fstype", "xfs", "ImageId", instance.ami, "InstanceType", instance.instance_type]
            ]
            view   = "gauge"
            region = var.aws_region
            title  = "${instance.name} - Disk Usage"
            period = 300
            stat   = "Average"
            yAxis = {
              left = {
                min = 0
                max = 100
              }
            }
            annotations = {
              horizontal = [
                {
                  value   = 70
                  label   = "Good"
                  color   = "#2ca02c" # green
                  fill    = "below"
                  yAxis   = "left"
                  visible = true
                },
                {
                  value   = 70
                  label   = "Warning"
                  color   = "#ff9900" # orange
                  fill    = "above"
                  yAxis   = "left"
                  visible = true
                },
                {
                  value   = 85
                  label   = "Critical"
                  color   = "#ff0000" # red
                  fill    = "above"
                  yAxis   = "left"
                  visible = true
                }
              ]
            }
            thresholds = [
              {
                value   = 70
                color   = "#2ca02c" # green
                fill    = "below"
                yAxis   = "left"
                visible = true
                label   = "Good"
              },
              {
                value   = 70
                color   = "#ff9900" # orange
                fill    = "above"
                yAxis   = "left"
                visible = true
                label   = "Warning"
              },
              {
                value   = 85
                color   = "#ff0000" # red
                fill    = "above"
                yAxis   = "left"
                visible = true
                label   = "Critical"
              }
            ]
          }
        }
      ]
    )
  })
}

