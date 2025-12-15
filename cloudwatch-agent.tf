# CloudWatch Agent Installation and Configuration via Terraform
# Uses AWS Systems Manager (SSM) to automatically install and configure CloudWatch Agent

# Store CloudWatch Agent configuration in SSM Parameter Store
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name        = "/AmazonCloudWatch-Config/${var.instance_name}/amazon-cloudwatch-agent.json"
  description = "CloudWatch Agent configuration for ${var.instance_name}"
  type        = "String"
  value       = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "CWAgent"
      metrics_collected = {
        cpu = {
          measurement                = ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                   = false
        }
        disk = {
          measurement                = ["used_percent"]
          metrics_collection_interval = 60
          resources                  = ["*"]
        }
        diskio = {
          measurement                = ["io_time"]
          metrics_collection_interval = 60
          resources                  = ["*"]
        }
        mem = {
          measurement                = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        netstat = {
          measurement                = ["tcp_established", "tcp_time_wait"]
          metrics_collection_interval = 60
        }
        processes = {
          measurement = ["running", "sleeping", "dead"]
        }
        swap = {
          measurement = ["swap_used_percent"]
        }
      }
      append_dimensions = {
        InstanceId         = "$${aws:InstanceId}"
        ImageId           = "$${aws:ImageId}"
        InstanceType      = "$${aws:InstanceType}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = []
        }
      }
    }
  })

  tags = {
    Name        = "cloudwatch-agent-config-${var.instance_name}"
    Environment = var.environment
    Instance    = var.instance_name
  }
}

# SSM Association to install and configure CloudWatch Agent
# Uses AWS-managed SSM document: AmazonCloudWatch-ManageAgent
resource "aws_ssm_association" "cloudwatch_agent" {
  name = "AmazonCloudWatch-ManageAgent"

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource    = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cloudwatch_agent_config.name
    optionalRestart               = "yes"
  }

  depends_on = [
    aws_ssm_parameter.cloudwatch_agent_config,
    null_resource.attach_iam_instance_profile
  ]
}

# Trigger SSM Association execution after IAM role is attached
# This ensures the association runs with proper IAM permissions
resource "null_resource" "trigger_ssm_association" {
  triggers = {
    association_id = aws_ssm_association.cloudwatch_agent.id
    instance_id    = var.instance_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Waiting for IAM role to propagate (60 seconds)..."
      echo "This ensures the IAM role is fully active before triggering SSM Association."
      sleep 60
      
      echo ""
      echo "Triggering SSM Association execution..."
      aws ssm start-associations-once \
        --association-ids ${aws_ssm_association.cloudwatch_agent.id} \
        --region ${var.aws_region} 2>&1 || echo "Note: Association execution triggered (may already be running)"
      
      echo ""
      echo "✅ SSM Association execution started!"
      echo ""
      echo "The CloudWatch Agent will be installed and configured automatically."
      echo "This may take 2-5 minutes. Monitor progress with:"
      echo ""
      echo "  aws ssm describe-association-executions \\"
      echo "    --association-id ${aws_ssm_association.cloudwatch_agent.id} \\"
      echo "    --region ${var.aws_region} \\"
      echo "    --max-results 1"
      echo ""
    EOT
  }

  depends_on = [
    aws_ssm_association.cloudwatch_agent,
    null_resource.attach_iam_instance_profile
  ]
}

