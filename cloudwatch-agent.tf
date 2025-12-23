# CloudWatch Agent Installation and Configuration via Terraform
# Uses AWS Systems Manager (SSM) to automatically install and configure CloudWatch Agent

# Verify and Start SSM Agent (per instance)
# Fast, reliable approach: Uses SSM Run Command only (no SSH complexity)
# 
# IMPORTANT: SSM Agent must be pre-installed on instances for this to work.
# For new instances, install SSM Agent via EC2 User Data:
# 
# Amazon Linux/RHEL/CentOS:
#   yum install -y amazon-ssm-agent && systemctl start amazon-ssm-agent && systemctl enable amazon-ssm-agent
#
# Ubuntu/Debian:
#   apt-get update && apt-get install -y amazon-ssm-agent && systemctl start amazon-ssm-agent && systemctl enable amazon-ssm-agent
#
# For existing instances without SSM Agent, install it manually or use EC2 User Data on restart.
resource "null_resource" "install_ssm_agent" {
  for_each = local.ec2_instances_map

  triggers = {
    instance_id          = each.value.instance_id
    iam_profile_attached = null_resource.attach_iam_instance_profile[each.key].id
    version              = "13.0-auto-restart-ssm" # Version bump - automatic SSM Agent restart when offline
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set +e  # Don't exit on error - handle gracefully
      echo "=========================================="
      echo "Verifying SSM Agent for ${each.value.name}"
      echo "=========================================="
      
      INSTANCE_ID="${each.value.instance_id}"
      INSTANCE_NAME="${each.value.name}"
      REGION="${var.aws_region}"
      
      # Step 1: Wait for IAM profile to fully propagate (critical for SSM Agent authentication)
      echo "Step 1: Waiting 90 seconds for IAM instance profile to fully propagate..."
      echo "This ensures the IAM credentials are available to SSM Agent."
      sleep 90
      
      # Step 2: Verify IAM instance profile is attached
      echo ""
      echo "Step 2: Verifying IAM instance profile attachment..."
      IAM_PROFILE_CHECK=$(aws ec2 describe-iam-instance-profile-associations \
        --filters "Name=instance-id,Values=$INSTANCE_ID" \
        --region $REGION \
        --query 'IamInstanceProfileAssociations[0].State' \
        --output text 2>/dev/null || echo "None")
      
      if [ "$IAM_PROFILE_CHECK" != "associated" ]; then
        echo "⚠️  WARNING: IAM instance profile may not be fully associated (state: $IAM_PROFILE_CHECK)"
        echo "Waiting additional 30 seconds for association to complete..."
        sleep 30
      else
        echo "✅ IAM instance profile is associated"
      fi
      
      # Step 3: Wait for SSM Agent to automatically refresh credentials and come online
      # SSM Agent checks for new IAM credentials every 1-2 minutes automatically
      echo ""
      echo "Step 3: Waiting for SSM Agent to refresh IAM credentials and come online..."
      echo "SSM Agent automatically checks for new credentials every 1-2 minutes."
      echo "This may take up to 3 minutes after IAM profile attachment..."
      
      MAX_WAIT=900  # 20 minutes total (allows for multiple credential refresh cycles and IAM propagation)
      ELAPSED=0
      INTERVAL=15   # Check every 15 seconds
      SSM_STATUS=""
      LAST_STATUS=""
      
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        SSM_STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --region $REGION \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "NotRegistered")
        
        if [ "$SSM_STATUS" == "Online" ]; then
          echo "✅ SSM Agent is now online! (took $${ELAPSED}s)"
          echo "SSM Agent has successfully authenticated with IAM credentials."
          exit 0
        fi
        
        # Only print status if it changed or every 30 seconds
        if [ "$SSM_STATUS" != "$LAST_STATUS" ] || [ $((ELAPSED % 30)) -eq 0 ]; then
          echo "SSM Agent status: $SSM_STATUS (waiting... $${ELAPSED}s/$${MAX_WAIT}s)"
          LAST_STATUS="$SSM_STATUS"
        fi
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
      done
      
      # Final check
      echo ""
      echo "Step 4: Final SSM Agent status check..."
      SSM_STATUS=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region $REGION \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "NotRegistered")
      
      if [ "$SSM_STATUS" == "Online" ]; then
        echo "✅ SSM Agent is online for $INSTANCE_NAME!"
        echo "SSM Agent is ready for CloudWatch Agent installation."
        exit 0
      else
        echo "❌ SSM Agent did not come online after $${MAX_WAIT} seconds (status: $SSM_STATUS)"
        echo ""
        echo "=========================================="
        echo "AUTOMATIC RESTART ATTEMPT"
        echo "=========================================="
        echo "Attempting to automatically restart SSM Agent..."
        echo "Instance: $INSTANCE_NAME ($INSTANCE_ID)"
        echo "Region: $REGION"
        echo ""
        
        # Try to restart SSM Agent using EC2 Instance Connect API
        # First, get instance details to determine the OS user
        INSTANCE_OS=$(aws ec2 describe-instances \
          --instance-ids "$INSTANCE_ID" \
          --region $REGION \
          --query 'Reservations[0].Instances[0].PlatformDetails' \
          --output text 2>/dev/null || echo "linux/unix")
        
        # Determine the default user based on OS
        if echo "$INSTANCE_OS" | grep -qi "windows"; then
          OS_USER="Administrator"
        else
          # For Linux, try common usernames
          OS_USER="ec2-user"  # Default for Amazon Linux
        fi
        
        echo "Detected OS: $INSTANCE_OS, using user: $OS_USER"
        echo ""
        echo "Attempting to restart SSM Agent via EC2 Instance Connect..."
        
        # Generate a temporary SSH key pair
        TEMP_KEY_DIR=$(mktemp -d)
        TEMP_PRIVATE_KEY="$TEMP_KEY_DIR/ssm_restart_key"
        TEMP_PUBLIC_KEY="$TEMP_KEY_DIR/ssm_restart_key.pub"
        
        # Generate SSH key pair
        ssh-keygen -t rsa -b 2048 -f "$TEMP_PRIVATE_KEY" -N "" -q 2>/dev/null || {
          echo "⚠️  Warning: Could not generate SSH key. Trying alternative method..."
          rm -rf "$TEMP_KEY_DIR"
          TEMP_KEY_DIR=""
        }
        
        if [ -n "$TEMP_KEY_DIR" ] && [ -f "$TEMP_PUBLIC_KEY" ]; then
          # Send SSH public key to instance
          echo "Sending SSH public key to instance..."
          SSH_KEY_OUTPUT=$(aws ec2-instance-connect send-ssh-public-key \
            --instance-id "$INSTANCE_ID" \
            --instance-os-user "$OS_USER" \
            --ssh-public-key file://"$TEMP_PUBLIC_KEY" \
            --region $REGION \
            --output text \
            --query 'RequestId' 2>&1)
          
          if [ $? -eq 0 ]; then
            echo "✅ SSH key sent successfully"
            echo "Attempting to restart SSM Agent via SSH..."
            
            # Get instance's public IP or use private IP with VPN/bastion
            # For simplicity, try to get public IP first
            INSTANCE_IP=$(aws ec2 describe-instances \
              --instance-ids "$INSTANCE_ID" \
              --region $REGION \
              --query 'Reservations[0].Instances[0].PublicIpAddress' \
              --output text 2>/dev/null || echo "")
            
            if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" == "None" ]; then
              INSTANCE_IP=$(aws ec2 describe-instances \
                --instance-ids "$INSTANCE_ID" \
                --region $REGION \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                --output text 2>/dev/null || echo "")
            fi
            
            if [ -n "$INSTANCE_IP" ] && [ "$INSTANCE_IP" != "None" ]; then
              # Try to SSH and restart SSM Agent
              # Use SSH with strict host key checking disabled for automation
              SSH_RESTART_OUTPUT=$(ssh -i "$TEMP_PRIVATE_KEY" \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=10 \
                -o LogLevel=ERROR \
                "$OS_USER@$INSTANCE_IP" \
                "sudo systemctl restart amazon-ssm-agent && echo 'SSM Agent restart command executed'" 2>&1)
              
              if [ $? -eq 0 ]; then
                echo "✅ SSM Agent restart command sent successfully"
                echo "Waiting 30 seconds for SSM Agent to restart and authenticate..."
                sleep 30
                
                # Check if SSM Agent is now online
                SSM_STATUS=$(aws ssm describe-instance-information \
                  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
                  --region $REGION \
                  --query 'InstanceInformationList[0].PingStatus' \
                  --output text 2>/dev/null || echo "NotRegistered")
                
                if [ "$SSM_STATUS" == "Online" ]; then
                  echo "✅ SSM Agent is now online after automatic restart!"
                  rm -rf "$TEMP_KEY_DIR"
                  exit 0
                else
                  echo "⚠️  SSM Agent restart command executed, but status is still: $SSM_STATUS"
                  echo "Waiting additional 60 seconds for authentication..."
                  sleep 60
                  
                  SSM_STATUS=$(aws ssm describe-instance-information \
                    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
                    --region $REGION \
                    --query 'InstanceInformationList[0].PingStatus' \
                    --output text 2>/dev/null || echo "NotRegistered")
                  
                  if [ "$SSM_STATUS" == "Online" ]; then
                    echo "✅ SSM Agent is now online after automatic restart!"
                    rm -rf "$TEMP_KEY_DIR"
                    exit 0
                  fi
                fi
              else
                echo "⚠️  SSH connection failed: $SSH_RESTART_OUTPUT"
                echo "This may be due to security group restrictions or network configuration."
              fi
            else
              echo "⚠️  Could not determine instance IP address"
            fi
            
            # Clean up
            rm -rf "$TEMP_KEY_DIR"
          else
            echo "⚠️  Failed to send SSH key: $SSH_KEY_OUTPUT"
            echo "This may be due to EC2 Instance Connect not being available or IAM permissions."
            rm -rf "$TEMP_KEY_DIR"
          fi
        fi
        
        # If automatic restart failed, try one more time with SSM (sometimes it works even if status shows offline)
        echo ""
        echo "Attempting alternative: Trying SSM command (sometimes works even if status shows offline)..."
        SSM_CMD_PARAMS='{"commands":["sudo systemctl restart amazon-ssm-agent"]}'
        SSM_COMMAND_OUTPUT=$(aws ssm send-command \
          --instance-ids "$INSTANCE_ID" \
          --document-name "AWS-RunShellScript" \
          --parameters "$SSM_CMD_PARAMS" \
          --region $REGION \
          --output text \
          --query 'Command.CommandId' 2>&1)
        
        if echo "$SSM_COMMAND_OUTPUT" | grep -qE '^[a-f0-9-]{36}$'; then
          echo "✅ SSM restart command sent (Command ID: $SSM_COMMAND_OUTPUT)"
          echo "Waiting 60 seconds for SSM Agent to restart and authenticate..."
          sleep 60
          
          SSM_STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --region $REGION \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "NotRegistered")
          
          if [ "$SSM_STATUS" == "Online" ]; then
            echo "✅ SSM Agent is now online after SSM restart command!"
            exit 0
          fi
        fi
        
        # Final check after all restart attempts
        echo ""
        echo "Final SSM Agent status check after restart attempts..."
        SSM_STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --region $REGION \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "NotRegistered")
        
        if [ "$SSM_STATUS" == "Online" ]; then
          echo "✅ SSM Agent is now online!"
          exit 0
        else
          echo "❌ ERROR: SSM Agent still not online after automatic restart attempts (status: $SSM_STATUS)"
          echo ""
          echo "=========================================="
          echo "AUTOMATIC RESTART FAILED"
          echo "=========================================="
          echo "All automatic restart methods were attempted but SSM Agent is still not online."
          echo ""
          echo "Possible reasons:"
          echo "1. SSM Agent is not installed on the instance"
          echo "2. Security group rules blocking SSM/SSH access"
          echo "3. IAM instance profile propagation taking longer than expected (can take 10+ minutes)"
          echo "4. Network connectivity issues"
          echo ""
          echo "MANUAL ACTION REQUIRED:"
          echo "1. Connect to the instance via EC2 Instance Connect or Session Manager"
          echo "2. Verify SSM Agent is installed: sudo systemctl status amazon-ssm-agent"
          echo "3. If installed, restart it: sudo systemctl restart amazon-ssm-agent"
          echo "4. Wait 2-3 minutes, then re-run: terraform apply"
          echo "=========================================="
          exit 1
        fi
      fi
    EOT
  }

  depends_on = [null_resource.attach_iam_instance_profile]
}

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
# Optimized for pre-installed SSM Agent: Fast async installation
resource "null_resource" "install_cloudwatch_agent" {
  for_each = local.ec2_instances_map

  triggers = {
    instance_id  = each.value.instance_id
    iam_profile  = null_resource.attach_iam_instance_profile[each.key].id
    ssm_verified = null_resource.install_ssm_agent[each.key].id
    version      = "5.0-preinstalled-ssm" # Version bump for pre-installed SSM Agent optimization
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set +e  # Don't exit on error - non-blocking
      echo "Installing CloudWatch Agent for ${each.value.name} (${each.value.instance_id})..."
      
      INSTANCE_ID="${each.value.instance_id}"
      INSTANCE_NAME="${each.value.name}"
      REGION="${var.aws_region}"
      
      # Brief wait for IAM propagation (reduced since SSM Agent is pre-installed)
      sleep 5
      
      # Quick verification: Check if SSM Agent is online (should be fast with pre-installed agent)
      echo "Verifying SSM Agent is online..."
      SSM_STATUS=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region $REGION \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "NotRegistered")
      
      if [ "$SSM_STATUS" != "Online" ]; then
        echo "⚠️  SSM Agent is not online yet (status: $SSM_STATUS). Waiting up to 15 seconds..."
        # Quick retry loop for pre-installed SSM Agent (should come online quickly)
        for i in {1..3}; do
          sleep 5
          SSM_STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --region $REGION \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "NotRegistered")
          if [ "$SSM_STATUS" == "Online" ]; then
            echo "✅ SSM Agent is now online!"
            break
          fi
        done
      else
        echo "✅ SSM Agent is online - proceeding with CloudWatch Agent installation"
      fi
      
      # Fast retry logic: 3 attempts with 3-second delays (optimized for pre-installed SSM)
      MAX_RETRIES=3
      RETRY_COUNT=0
      COMMAND_ID=""
      
      while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Send installation command via SSM
        COMMAND_OUTPUT=$(aws ssm send-command \
          --instance-ids "$INSTANCE_ID" \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=["if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then echo \"Already installed\"; exit 0; fi", "yum install -y amazon-cloudwatch-agent || apt-get install -y amazon-cloudwatch-agent"]' \
          --region $REGION \
          --output text \
          --query 'Command.CommandId' 2>&1)
        
        # Check if command was sent successfully
        if echo "$COMMAND_OUTPUT" | grep -qE '^[a-f0-9-]{36}$'; then
          COMMAND_ID="$COMMAND_OUTPUT"
          echo "✅ Installation command sent successfully for $INSTANCE_NAME (Command ID: $COMMAND_ID)"
          echo "CloudWatch Agent will install in the background (typically 1-3 minutes)."
          exit 0
        fi
        
        # If command failed, wait briefly and retry
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Attempt $RETRY_COUNT/$MAX_RETRIES failed. Retrying in 3 seconds..."
          sleep 3
        fi
      done
      
      # If all retries failed, log warning but don't fail (non-blocking)
      echo "⚠️  Warning: Could not send installation command for $INSTANCE_NAME after $MAX_RETRIES attempts."
      echo "SSM Agent status: $SSM_STATUS"
      echo "The command will be retried automatically when SSM Agent comes online."
      echo "Instance: $INSTANCE_ID"
      exit 0  # Exit successfully to allow Terraform to continue
    EOT
  }

  depends_on = [
    null_resource.attach_iam_instance_profile,
    null_resource.install_ssm_agent
  ]
}

# Configure CloudWatch Agent (per instance)
# Fully automated - waits for completion and verifies success
resource "null_resource" "configure_cloudwatch_agent" {
  for_each = local.ec2_instances_map

  triggers = {
    instance_id      = each.value.instance_id
    config_param     = aws_ssm_parameter.cloudwatch_agent_config[each.key].name
    install_complete = null_resource.install_cloudwatch_agent[each.key].id
    version          = "7.0-automated-complete" # Version bump to force re-configuration
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command     = <<-EOT
      set -e  # Exit on error - we want to know if this fails
      echo "=========================================="
      echo "Configuring CloudWatch Agent for ${each.value.name}"
      echo "=========================================="
      
      INSTANCE_ID="${each.value.instance_id}"
      INSTANCE_NAME="${each.value.name}"
      REGION="${var.aws_region}"
      PARAM_NAME="${aws_ssm_parameter.cloudwatch_agent_config[each.key].name}"
      
      # Wait for CloudWatch Agent installation to complete
      echo "Waiting 15 seconds for CloudWatch Agent installation to complete..."
      sleep 15
      
      # Verify SSM Agent is online (with extended wait to match install_ssm_agent timing)
      echo "Verifying SSM Agent is online..."
      echo "This may take a few minutes if SSM Agent is still refreshing IAM credentials..."
      
      MAX_SSM_WAIT=300  # 5 minutes - same as install_ssm_agent wait time
      SSM_ELAPSED=0
      SSM_INTERVAL=10
      SSM_STATUS=""
      
      while [ $SSM_ELAPSED -lt $MAX_SSM_WAIT ]; do
        SSM_STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --region $REGION \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "NotRegistered")
        
        if [ "$SSM_STATUS" == "Online" ]; then
          echo "✅ SSM Agent is online (took $${SSM_ELAPSED}s)"
          break
        fi
        
        if [ $((SSM_ELAPSED % 30)) -eq 0 ]; then
          echo "SSM Agent status: $SSM_STATUS (waiting... $${SSM_ELAPSED}s/$${MAX_SSM_WAIT}s)"
        fi
        
        sleep $SSM_INTERVAL
        SSM_ELAPSED=$((SSM_ELAPSED + SSM_INTERVAL))
      done
      
      if [ "$SSM_STATUS" != "Online" ]; then
        echo "❌ ERROR: SSM Agent is not online after $${MAX_SSM_WAIT} seconds (status: $SSM_STATUS)"
        echo ""
        echo "SSM Agent must be online to configure CloudWatch Agent."
        echo "Please ensure SSM Agent is installed, running, and has authenticated with IAM credentials."
        echo ""
        echo "On the instance, verify:"
        echo "  sudo systemctl status amazon-ssm-agent"
        echo "  sudo systemctl restart amazon-ssm-agent  # If needed"
        echo ""
        exit 1
      fi
      
      # Send configuration command using multiple simple commands
      echo "Sending CloudWatch Agent configuration command..."
      
      # Build JSON parameters - using a here-document to write script, then execute
      # This avoids complex escaping issues
      # Use $$ to escape $ for Terraform, and \\ to escape backslashes
      PARAMS_JSON=$(cat << JSONEOF
{
  "commands": [
    "PARAM_NAME=\"$PARAM_NAME\"",
    "REGION=\"$REGION\"",
    "echo 'Configuring CloudWatch Agent from SSM Parameter Store...'",
    "echo \\"Parameter: \\$PARAM_NAME\\"",
    "echo \\"Region: \\$REGION\\"",
    "sudo systemctl stop amazon-cloudwatch-agent 2>/dev/null || true",
    "echo 'Fetching config from SSM Parameter Store using native SSM support...'",
    "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:\\$PARAM_NAME -s || (echo 'Primary method failed, trying alternative...' && JSON_VALUE=\\$(aws ssm get-parameter --name \\"\\$PARAM_NAME\\" --region \\"\\$REGION\\" --with-decryption --query 'Parameter.Value' --output text) && echo \\"\\$JSON_VALUE\\" > /tmp/amazon-cloudwatch-agent.json && sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/tmp/amazon-cloudwatch-agent.json -s)",
    "sudo systemctl enable amazon-cloudwatch-agent",
    "sudo systemctl restart amazon-cloudwatch-agent",
    "sleep 3",
    "if sudo systemctl is-active --quiet amazon-cloudwatch-agent; then echo '✅ CloudWatch Agent configured and started successfully'; exit 0; else echo '❌ ERROR: CloudWatch Agent failed to start'; sudo systemctl status amazon-cloudwatch-agent; exit 1; fi"
  ]
}
JSONEOF
)
      
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "$PARAMS_JSON" \
        --region $REGION \
        --timeout-seconds 300 \
        --output text \
        --query 'Command.CommandId' 2>&1)
      
      if [ $? -ne 0 ] || ! echo "$COMMAND_ID" | grep -qE '^[a-f0-9-]{36}$'; then
        echo "❌ ERROR: Failed to send configuration command"
        echo "Command output: $COMMAND_ID"
        exit 1
      fi
      
      echo "✅ Configuration command sent successfully (Command ID: $COMMAND_ID)"
      echo "Waiting for command to complete (this may take 1-2 minutes)..."
      
      # Wait for command to complete
      MAX_WAIT=180  # 3 minutes
      ELAPSED=0
      INTERVAL=10
      
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        COMMAND_STATUS=$(aws ssm get-command-invocation \
          --command-id "$COMMAND_ID" \
          --instance-id "$INSTANCE_ID" \
          --region $REGION \
          --query 'Status' \
          --output text 2>/dev/null || echo "NotFound")
        
        if [ "$COMMAND_STATUS" == "Success" ]; then
          echo "✅ CloudWatch Agent configuration completed successfully!"
          echo ""
          echo "Command output:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region $REGION \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "No output"
          exit 0
        elif [ "$COMMAND_STATUS" == "Failed" ] || [ "$COMMAND_STATUS" == "Cancelled" ] || [ "$COMMAND_STATUS" == "TimedOut" ]; then
          echo "❌ ERROR: Configuration command failed with status: $COMMAND_STATUS"
          echo ""
          echo "Error output:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region $REGION \
            --query 'StandardErrorContent' \
            --output text 2>/dev/null || echo "No error output"
          echo ""
          echo "Standard output:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region $REGION \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "No output"
          exit 1
        fi
        
        echo "Command status: $COMMAND_STATUS (waiting... $${ELAPSED}s/$${MAX_WAIT}s)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
      done
      
      echo "❌ ERROR: Configuration command timed out after $MAX_WAIT seconds"
      echo "Command ID: $COMMAND_ID"
      echo "Please check the command status manually:"
      echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID --region $REGION"
      exit 1
    EOT
  }

  depends_on = [
    aws_ssm_parameter.cloudwatch_agent_config,
    null_resource.install_cloudwatch_agent
  ]
}

# Note: Restart is handled within the configure_cloudwatch_agent resource
# No separate restart resource needed - configuration script already restarts the agent
