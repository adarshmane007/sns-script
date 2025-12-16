# CloudWatch Agent Installation and Configuration via Terraform
# Uses AWS Systems Manager (SSM) to automatically install and configure CloudWatch Agent

# Store CloudWatch Agent configuration in SSM Parameter Store (per instance)
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  for_each = local.ec2_instances_map
  
  name        = "/AmazonCloudWatch-Config/${each.value.name}/amazon-cloudwatch-agent.json"
  description = "CloudWatch Agent configuration for ${each.value.name}"
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
    Name        = "cloudwatch-agent-config-${each.value.name}"
    Environment = var.environment
    Instance    = each.value.name
  }
}

# Install CloudWatch Agent (per instance)
# Fully automated with extended wait times and retry logic
resource "null_resource" "install_cloudwatch_agent" {
  for_each = local.ec2_instances_map
  
  triggers = {
    instance_id = each.value.instance_id
    iam_profile = null_resource.attach_iam_instance_profile[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e
      echo "=========================================="
      echo "Installing CloudWatch Agent for ${each.value.name}"
      echo "=========================================="
      echo ""
      
      # Wait for IAM role to propagate
      echo "Step 1: Waiting for IAM role to propagate (90 seconds)..."
      sleep 90
      
      # Extended wait for SSM registration (up to 20 minutes)
      echo ""
      echo "Step 2: Waiting for instance ${each.value.name} (${each.value.instance_id}) to register with SSM..."
      echo "This can take 5-20 minutes after IAM profile attachment..."
      MAX_SSM_WAIT=1200  # 20 minutes
      SSM_WAIT_COUNT=0
      SSM_STATUS="NotRegistered"
      
      while [ $SSM_WAIT_COUNT -lt $MAX_SSM_WAIT ]; do
        SSM_STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${each.value.instance_id}" \
          --region ${var.aws_region} \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "NotRegistered")
        
        if [ "$SSM_STATUS" == "Online" ]; then
          echo ""
          echo "✅ Instance ${each.value.name} is registered with SSM and online!"
          break
        fi
        
        # Print status every 60 seconds
        if [ $((SSM_WAIT_COUNT % 60)) -eq 0 ] && [ $SSM_WAIT_COUNT -gt 0 ]; then
          MINUTES=$((SSM_WAIT_COUNT / 60))
          echo "Still waiting for SSM registration... ($${MINUTES} minutes elapsed)"
        fi
        sleep 10
        SSM_WAIT_COUNT=$((SSM_WAIT_COUNT + 10))
      done
      
      if [ "$SSM_STATUS" != "Online" ]; then
        echo ""
        echo "⚠️  Warning: Instance ${each.value.name} not registered with SSM after 20 minutes."
        echo "This may indicate SSM Agent is not running or IAM permissions issue."
        echo "Attempting installation anyway - it will retry if SSM becomes available..."
      fi
      
      # Retry logic for installation command
      echo ""
      echo "Step 3: Installing CloudWatch Agent on ${each.value.name}..."
      MAX_RETRIES=10
      RETRY_COUNT=0
      INSTALL_SUCCESS=false
      
      while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Check SSM status before each retry
        SSM_CHECK=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${each.value.instance_id}" \
          --region ${var.aws_region} \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "NotRegistered")
        
        if [ "$SSM_CHECK" != "Online" ]; then
          echo "SSM not ready yet, waiting 30 seconds before retry $((RETRY_COUNT + 1))/$MAX_RETRIES..."
          sleep 30
          RETRY_COUNT=$((RETRY_COUNT + 1))
          continue
        fi
        
        # Try to send command
        echo "Attempting to send installation command (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
        COMMAND_OUTPUT=$(aws ssm send-command \
          --instance-ids "${each.value.instance_id}" \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=["if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then echo \"Already installed\"; exit 0; fi", "yum install -y amazon-cloudwatch-agent || apt-get install -y amazon-cloudwatch-agent"]' \
          --region ${var.aws_region} \
          --output text \
          --query 'Command.CommandId' 2>&1) || COMMAND_OUTPUT="ERROR"
        
        if [[ "$COMMAND_OUTPUT" == *"Command.CommandId"* ]] || [[ "$COMMAND_OUTPUT" =~ ^[a-f0-9-]+$ ]]; then
          COMMAND_ID=$(echo "$COMMAND_OUTPUT" | grep -oE '[a-f0-9-]{36}' | head -1)
          if [ ! -z "$COMMAND_ID" ]; then
            echo "✅ Installation command sent successfully!"
            echo "Command ID: $COMMAND_ID"
            INSTALL_SUCCESS=true
            break
          fi
        fi
        
        # If command failed, check error
        if [[ "$COMMAND_OUTPUT" == *"InvalidInstanceId"* ]] || [[ "$COMMAND_OUTPUT" == *"not in a valid state"* ]]; then
          echo "Instance not ready for SSM commands yet, waiting 60 seconds..."
          sleep 60
        else
          echo "Command failed: $COMMAND_OUTPUT"
          echo "Waiting 30 seconds before retry..."
          sleep 30
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
      done
      
      if [ "$INSTALL_SUCCESS" = false ]; then
        echo ""
        echo "❌ Failed to send installation command after $MAX_RETRIES attempts."
        echo "The instance may need more time to register with SSM."
        echo "You can retry by running: terraform apply -replace=null_resource.install_cloudwatch_agent[\"${each.value.name}\"]"
        exit 1
      fi
      
      echo ""
      echo "=========================================="
      echo "CloudWatch Agent installation initiated for ${each.value.name}"
      echo "=========================================="
    EOT
  }

  depends_on = [null_resource.attach_iam_instance_profile]
}

# Configure CloudWatch Agent (per instance)
# Waits for installation to complete and then configures the agent
resource "null_resource" "configure_cloudwatch_agent" {
  for_each = local.ec2_instances_map
  
  triggers = {
    instance_id      = each.value.instance_id
    config_param     = aws_ssm_parameter.cloudwatch_agent_config[each.key].name
    install_complete = null_resource.install_cloudwatch_agent[each.key].id
    version          = "3.2" # Updated with retry logic
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e
      echo ""
      echo "=========================================="
      echo "Configuring CloudWatch Agent for ${each.value.name}"
      echo "=========================================="
      echo ""
      
      # Wait for SSM to be ready
      echo "Waiting for SSM to be ready..."
      MAX_SSM_WAIT=600  # 10 minutes
      SSM_WAIT_COUNT=0
      while [ $SSM_WAIT_COUNT -lt $MAX_SSM_WAIT ]; do
        SSM_STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${each.value.instance_id}" \
          --region ${var.aws_region} \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "NotRegistered")
        
        if [ "$SSM_STATUS" == "Online" ]; then
          echo "✅ SSM is ready!"
          break
        fi
        sleep 10
        SSM_WAIT_COUNT=$((SSM_WAIT_COUNT + 10))
      done
      
      # Wait a bit more for installation to complete
      echo "Waiting 30 seconds for installation to complete..."
      sleep 30
      
      # Retry logic for configuration
      MAX_RETRIES=10
      RETRY_COUNT=0
      CONFIG_SUCCESS=false
      
      while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo ""
        echo "Attempting to configure CloudWatch Agent (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
        
        CONFIG_SCRIPT="aws ssm get-parameter --name '${aws_ssm_parameter.cloudwatch_agent_config[each.key].name}' --region ${var.aws_region} --query 'Parameter.Value' --output text | tr -d '\r' > /tmp/amazon-cloudwatch-agent.json && if python3 -m json.tool /tmp/amazon-cloudwatch-agent.json > /dev/null 2>&1; then echo 'JSON is valid'; else echo 'JSON validation failed - checking file...'; cat /tmp/amazon-cloudwatch-agent.json | head -5; exit 1; fi && sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/tmp/amazon-cloudwatch-agent.json -s && sudo systemctl enable amazon-cloudwatch-agent && sudo systemctl restart amazon-cloudwatch-agent"
        
        COMMAND_OUTPUT=$(aws ssm send-command \
          --instance-ids "${each.value.instance_id}" \
          --document-name "AWS-RunShellScript" \
          --parameters "commands=[\"$CONFIG_SCRIPT\"]" \
          --region ${var.aws_region} \
          --output text \
          --query 'Command.CommandId' 2>&1) || COMMAND_OUTPUT="ERROR"
        
        if [[ "$COMMAND_OUTPUT" =~ ^[a-f0-9-]{36}$ ]]; then
          COMMAND_ID="$COMMAND_OUTPUT"
          echo "✅ Configuration command sent successfully!"
          echo "Command ID: $COMMAND_ID"
          
          # Wait for command to complete
          echo "Waiting for configuration to complete..."
          MAX_WAIT=300
          WAIT_COUNT=0
          while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            STATUS=$(aws ssm get-command-invocation \
              --command-id "$COMMAND_ID" \
              --instance-id "${each.value.instance_id}" \
              --region ${var.aws_region} \
              --query 'Status' \
              --output text 2>/dev/null || echo "InProgress")
            
            if [ "$STATUS" == "Success" ]; then
              echo "✅ CloudWatch Agent configured successfully!"
              CONFIG_SUCCESS=true
              break
            elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
              echo "Configuration command failed with status: $STATUS"
              break
            fi
            sleep 5
            WAIT_COUNT=$((WAIT_COUNT + 5))
          done
          
          if [ "$CONFIG_SUCCESS" = true ]; then
            break
          fi
        else
          echo "Failed to send command: $COMMAND_OUTPUT"
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Waiting 30 seconds before retry..."
          sleep 30
        fi
      done
      
      if [ "$CONFIG_SUCCESS" = false ]; then
        echo ""
        echo "⚠️  Warning: Could not confirm configuration completion."
        echo "The agent may still be configuring. Check status manually if needed."
      fi
      
      echo ""
      echo "=========================================="
      echo "Configuration process completed for ${each.value.name}"
      echo "=========================================="
    EOT
  }

  depends_on = [
    aws_ssm_parameter.cloudwatch_agent_config,
    null_resource.install_cloudwatch_agent
  ]
}

# Restart CloudWatch Agent after IAM instance profile changes (per instance)
# This ensures the agent picks up new IAM credentials
resource "null_resource" "restart_cloudwatch_agent_after_iam_change" {
  for_each = local.ec2_instances_map
  
  triggers = {
    instance_id          = each.value.instance_id
    iam_profile_attached = null_resource.attach_iam_instance_profile[each.key].id
    agent_configured     = null_resource.configure_cloudwatch_agent[each.key].id
    version              = "2.0" # Force recreation to ensure restart happens
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e
      
      echo ""
      echo "=========================================="
      echo "Restarting CloudWatch Agent for ${each.value.name} to refresh IAM credentials"
      echo "=========================================="
      echo ""
      echo "Waiting 15 seconds for IAM credentials to propagate..."
      sleep 15
      
      echo ""
      echo "Step 1: Stopping CloudWatch Agent on ${each.value.name}..."
      STOP_CMD=$(aws ssm send-command \
        --instance-ids "${each.value.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo systemctl stop amazon-cloudwatch-agent"]' \
        --region ${var.aws_region} \
        --timeout-seconds 30 \
        --output text \
        --query 'Command.CommandId' 2>/dev/null || echo "")
      
      if [ ! -z "$STOP_CMD" ]; then
        echo "Stop command ID: $STOP_CMD"
        sleep 5
      fi
      
      echo ""
      echo "Step 2: Waiting 5 seconds for credentials to refresh..."
      sleep 5
      
      echo ""
      echo "Step 3: Starting CloudWatch Agent with new credentials on ${each.value.name}..."
      RESTART_CMD=$(aws ssm send-command \
        --instance-ids "${each.value.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo systemctl start amazon-cloudwatch-agent && sleep 3 && sudo systemctl is-active amazon-cloudwatch-agent && echo \"Agent is active\" || echo \"Agent failed to start\""]' \
        --region ${var.aws_region} \
        --timeout-seconds 60 \
        --output text \
        --query 'Command.CommandId')
      
      echo "Restart command ID: $RESTART_CMD"
      echo "Waiting for restart to complete (this may take up to 2 minutes)..."
      
      MAX_ATTEMPTS=30
      SUCCESS=false
      
      for i in $(seq 1 $MAX_ATTEMPTS); do
        STATUS=$(aws ssm get-command-invocation \
          --command-id "$RESTART_CMD" \
          --instance-id "${each.value.instance_id}" \
          --region ${var.aws_region} \
          --query 'Status' \
          --output text 2>/dev/null || echo "InProgress")
        
        if [ "$STATUS" == "Success" ]; then
          echo ""
          echo "✅ CloudWatch Agent restarted successfully for ${each.value.name}!"
          echo ""
          echo "Service Status Output:"
          OUTPUT=$(aws ssm get-command-invocation \
            --command-id "$RESTART_CMD" \
            --instance-id "${each.value.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
          echo "$OUTPUT"
          
          echo ""
          echo "Step 4: Verifying agent status and credentials for ${each.value.name}..."
          VERIFY_CMD=$(aws ssm send-command \
            --instance-ids "${each.value.instance_id}" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["sudo systemctl is-active amazon-cloudwatch-agent && aws sts get-caller-identity --region ${var.aws_region} 2>&1 | head -5"]' \
            --region ${var.aws_region} \
            --timeout-seconds 30 \
            --output text \
            --query 'Command.CommandId')
          
          sleep 8
          VERIFY_OUTPUT=$(aws ssm get-command-invocation \
            --command-id "$VERIFY_CMD" \
            --instance-id "${each.value.instance_id}" \
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
            --instance-id "${each.value.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo ""
          echo ""
          echo "Standard Error:"
          aws ssm get-command-invocation \
            --command-id "$RESTART_CMD" \
            --instance-id "${each.value.instance_id}" \
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
        echo "⚠️  Warning: Could not confirm restart completion for ${each.value.name}."
        echo "Command may still be executing. Check status manually:"
        echo "  aws ssm get-command-invocation --command-id $RESTART_CMD --instance-id ${each.value.instance_id} --region ${var.aws_region}"
        echo ""
        echo "You may need to manually restart the agent on the target server:"
        echo "  sudo systemctl restart amazon-cloudwatch-agent"
      fi
      
      echo ""
      echo "=========================================="
      echo "Restart process completed for ${each.value.name}."
      echo "CloudWatch Agent should now be using updated IAM credentials."
      echo "Monitor logs: sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
      echo "Metrics should start flowing within 5-10 minutes."
      echo "=========================================="
    EOT
  }

  depends_on = [
    null_resource.attach_iam_instance_profile,
    null_resource.configure_cloudwatch_agent
  ]
}
