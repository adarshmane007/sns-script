# CloudWatch Agent Installation and Configuration via Terraform
# Uses AWS Systems Manager (SSM) to automatically install and configure CloudWatch Agent

# Store CloudWatch Agent configuration in SSM Parameter Store
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name        = "/AmazonCloudWatch-Config/${var.instance_name}/amazon-cloudwatch-agent.json"
  description = "CloudWatch Agent configuration for ${var.instance_name}"
  type        = "String"
  overwrite   = true

  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "CWAgent"
      metrics_collected = {
        cpu = {
          measurement                 = ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                    = false
        }
        disk = {
          measurement                 = ["used_percent"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        diskio = {
          measurement                 = ["io_time"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        netstat = {
          measurement                 = ["tcp_established", "tcp_time_wait"]
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
        InstanceId           = "$${aws:InstanceId}"
        ImageId              = "$${aws:ImageId}"
        InstanceType         = "$${aws:InstanceType}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
    }
  })

  tags = {
    Name        = "cloudwatch-agent-config-${var.instance_name}"
    Environment = var.environment
    Instance    = var.instance_name
  }
}

resource "aws_ssm_parameter" "cloudwatch_agent_config_v3" {
  name        = "/AmazonCloudWatch-Config/${var.instance_name}/amazon-cloudwatch-agent-v3.json"
  description = "CloudWatch Agent configuration for ${var.instance_name}"
  type        = "String"
  overwrite   = true

  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "CWAgent"
      metrics_collected = {
        cpu = {
          measurement                 = ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                    = false
        }
        disk = {
          measurement                 = ["used_percent"]
          metrics_collection_interval = 60
          resources                   = ["/"]
          ignore_fs                   = ["tmpfs", "devtmpfs"]
        }
        diskio = {
          measurement                 = ["io_time"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        mem = {
          measurement                 = ["used_percent"]
          metrics_collection_interval = 60
        }
        netstat = {
          measurement                 = ["tcp_established", "tcp_time_wait"]
          metrics_collection_interval = 60
        }
        processes = {
          measurement = ["running", "sleeping", "dead"]
        }
        swap = {
          measurement = ["used_percent"]
        }
      }
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        ImageId              = "$${aws:ImageId}"
        InstanceType         = "$${aws:InstanceType}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
    }
  })

  tags = {
    Name        = "cloudwatch-agent-config-${var.instance_name}-v3"
    Environment = var.environment
    Instance    = var.instance_name
  }
}

# Install CloudWatch Agent
resource "null_resource" "install_cloudwatch_agent_v3" {
  triggers = {
    instance_id = var.instance_id
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e
      echo "Waiting for IAM role to propagate (60 seconds)..."
      sleep 60
      echo "Installing CloudWatch Agent on instance ${var.instance_id}..."
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${var.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then echo \"Already installed\"; exit 0; fi", "yum install -y amazon-cloudwatch-agent || apt-get install -y amazon-cloudwatch-agent"]' \
        --region ${var.aws_region} \
        --output text \
        --query 'Command.CommandId')
      echo "Command ID: $COMMAND_ID"
    EOT
  }

  depends_on = [null_resource.attach_iam_instance_profile]
}

# Configure CloudWatch Agent
resource "null_resource" "configure_cloudwatch_agent_v3" {
  triggers = {
    instance_id      = var.instance_id
    config_param     = aws_ssm_parameter.cloudwatch_agent_config_v3.name
    install_complete = null_resource.install_cloudwatch_agent_v3.id
    version          = "3.0"
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e
      echo "Configuring CloudWatch Agent on instance ${var.instance_id}..."
      CONFIG_SCRIPT="aws ssm get-parameter --name '${aws_ssm_parameter.cloudwatch_agent_config_v3.name}' --region ${var.aws_region} --query 'Parameter.Value' --output text > /tmp/amazon-cloudwatch-agent.json && sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/tmp/amazon-cloudwatch-agent.json -s && sudo systemctl enable amazon-cloudwatch-agent && sudo systemctl restart amazon-cloudwatch-agent"
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${var.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"$CONFIG_SCRIPT\"]" \
        --region ${var.aws_region} \
        --output text \
        --query 'Command.CommandId')
      echo "Command ID: $COMMAND_ID"
    EOT
  }

  depends_on = [
    aws_ssm_parameter.cloudwatch_agent_config_v3,
    null_resource.install_cloudwatch_agent_v3
  ]
}

# Restart CloudWatch Agent after IAM instance profile changes
# This ensures the agent picks up new IAM credentials
resource "null_resource" "restart_cloudwatch_agent_after_iam_change" {
  triggers = {
    instance_id          = var.instance_id
    iam_profile_attached = null_resource.attach_iam_instance_profile.id
    iam_profile_v3_attached = null_resource.attach_iam_instance_profile_v3.id
    agent_configured     = null_resource.configure_cloudwatch_agent_v3.id
    version              = "2.0" # Force recreation to ensure restart happens
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e
      
      echo ""
      echo "=========================================="
      echo "Restarting CloudWatch Agent to refresh IAM credentials"
      echo "=========================================="
      echo ""
      echo "Waiting 15 seconds for IAM credentials to propagate..."
      sleep 15
      
      echo ""
      echo "Step 1: Stopping CloudWatch Agent..."
      STOP_CMD=$(aws ssm send-command \
        --instance-ids "${var.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo systemctl stop amazon-cloudwatch-agent"]' \
        --region ${var.aws_region} \
        --timeout-seconds 30 \
        --output text \
        --query 'Command.CommandId' 2>/dev/null || echo "")
      
      if [ ! -z "$STOP_CMD" ]; then
        echo "Stop command ID: $STOP_CMD"
        # Wait briefly for stop
        sleep 5
      fi
      
      echo ""
      echo "Step 2: Waiting 5 seconds for credentials to refresh..."
      sleep 5
      
      echo ""
      echo "Step 3: Starting CloudWatch Agent with new credentials..."
      RESTART_CMD=$(aws ssm send-command \
        --instance-ids "${var.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo systemctl start amazon-cloudwatch-agent && sleep 3 && sudo systemctl is-active amazon-cloudwatch-agent && echo \"Agent is active\" || echo \"Agent failed to start\""]' \
        --region ${var.aws_region} \
        --timeout-seconds 60 \
        --output text \
        --query 'Command.CommandId')
      
      echo "Restart command ID: $RESTART_CMD"
      echo "Waiting for restart to complete (this may take up to 2 minutes)..."
      
      # Wait for command to complete with longer timeout
      MAX_ATTEMPTS=30
      SUCCESS=false
      
      for i in $(seq 1 $MAX_ATTEMPTS); do
        STATUS=$(aws ssm get-command-invocation \
          --command-id "$RESTART_CMD" \
          --instance-id "${var.instance_id}" \
          --region ${var.aws_region} \
          --query 'Status' \
          --output text 2>/dev/null || echo "InProgress")
        
        if [ "$STATUS" == "Success" ]; then
          echo ""
          echo "✅ CloudWatch Agent restarted successfully!"
          echo ""
          echo "Service Status Output:"
          OUTPUT=$(aws ssm get-command-invocation \
            --command-id "$RESTART_CMD" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
          echo "$OUTPUT"
          
          # Verify agent is actually running
          echo ""
          echo "Step 4: Verifying agent status and credentials..."
          VERIFY_CMD=$(aws ssm send-command \
            --instance-ids "${var.instance_id}" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["sudo systemctl is-active amazon-cloudwatch-agent && aws sts get-caller-identity --region ${var.aws_region} 2>&1 | head -5"]' \
            --region ${var.aws_region} \
            --timeout-seconds 30 \
            --output text \
            --query 'Command.CommandId')
          
          sleep 8
          VERIFY_OUTPUT=$(aws ssm get-command-invocation \
            --command-id "$VERIFY_CMD" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
          
          if [ ! -z "$VERIFY_OUTPUT" ]; then
            echo ""
            echo "Verification Output:"
            echo "$VERIFY_OUTPUT"
          fi
          
          SUCCESS=true
          break
        elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
          echo ""
          echo "⚠️  Restart command status: $STATUS"
          echo "Standard Output:"
          aws ssm get-command-invocation \
            --command-id "$RESTART_CMD" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo ""
          echo ""
          echo "Standard Error:"
          aws ssm get-command-invocation \
            --command-id "$RESTART_CMD" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardErrorContent' \
            --output text 2>/dev/null || echo ""
          break
        else
          if [ $((i % 5)) -eq 0 ]; then
            echo ""
            echo "Still waiting... ($i/$MAX_ATTEMPTS attempts, status: $STATUS)"
          else
            echo -n "."
          fi
          sleep 4
        fi
      done
      
      if [ "$SUCCESS" = false ]; then
        echo ""
        echo "⚠️  Warning: Could not confirm restart completion."
        echo "Command may still be executing. Check status manually:"
        echo "  aws ssm get-command-invocation --command-id $RESTART_CMD --instance-id ${var.instance_id} --region ${var.aws_region}"
        echo ""
        echo "You may need to manually restart the agent on the target server:"
        echo "  sudo systemctl restart amazon-cloudwatch-agent"
      fi
      
      echo ""
      echo "=========================================="
      echo "Restart process completed."
      echo "CloudWatch Agent should now be using updated IAM credentials."
      echo "Monitor logs: sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
      echo "Metrics should start flowing within 5-10 minutes."
      echo "=========================================="
    EOT
  }

  depends_on = [
    null_resource.attach_iam_instance_profile,
    null_resource.attach_iam_instance_profile_v3,
    null_resource.configure_cloudwatch_agent_v3
  ]
}
