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

# Install CloudWatch Agent first using SSM Run Command
# This must happen before configuration
resource "null_resource" "install_cloudwatch_agent" {
  triggers = {
    instance_id = var.instance_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Waiting for IAM role to propagate (60 seconds)..."
      sleep 60
      
      echo ""
      echo "Installing CloudWatch Agent on instance ${var.instance_id}..."
      
      # Send installation command via SSM
      # Using a simple one-liner approach that works reliably
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${var.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then echo \"Already installed\"; exit 0; fi", "if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; else echo \"Cannot detect OS\"; exit 1; fi", "if [[ \"$OS\" == \"amzn\" ]] || [[ \"$OS\" == \"rhel\" ]] || [[ \"$OS\" == \"centos\" ]]; then wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm -O /tmp/amazon-cloudwatch-agent.rpm && sudo rpm -U /tmp/amazon-cloudwatch-agent.rpm && rm -f /tmp/amazon-cloudwatch-agent.rpm && echo \"Installed for Amazon Linux/RHEL/CentOS\"; elif [[ \"$OS\" == \"ubuntu\" ]] || [[ \"$OS\" == \"debian\" ]]; then wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb && sudo dpkg -i -E /tmp/amazon-cloudwatch-agent.deb && rm -f /tmp/amazon-cloudwatch-agent.deb && echo \"Installed for Ubuntu/Debian\"; else echo \"Unsupported OS: $OS\"; exit 1; fi"]' \
        --region ${var.aws_region} \
        --output text \
        --query 'Command.CommandId')
      
      echo "Command ID: $COMMAND_ID"
      echo "Waiting for installation to complete (this may take 2-3 minutes)..."
      
      # Wait for command to complete
      for i in {1..30}; do
        STATUS=$(aws ssm get-command-invocation \
          --command-id "$COMMAND_ID" \
          --instance-id "${var.instance_id}" \
          --region ${var.aws_region} \
          --query 'Status' \
          --output text 2>/dev/null || echo "InProgress")
        
        if [ "$STATUS" == "Success" ]; then
          echo ""
          echo "✅ CloudWatch Agent installed successfully!"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text
          break
        elif [ "$STATUS" == "Failed" ]; then
          echo ""
          echo "❌ Installation failed!"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardErrorContent' \
            --output text
          exit 1
        else
          echo -n "."
          sleep 6
        fi
      done
      
      if [ "$STATUS" != "Success" ]; then
        echo ""
        echo "⚠️  Installation timed out. Status: $STATUS"
        echo "Check command status manually:"
        echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id ${var.instance_id} --region ${var.aws_region}"
      fi
    EOT
  }

  depends_on = [
    null_resource.attach_iam_instance_profile
  ]
}

# Configure CloudWatch Agent directly via SSM Run Command
# This is more reliable than SSM Association for configuration
resource "null_resource" "configure_cloudwatch_agent" {
  triggers = {
    instance_id     = var.instance_id
    config_param    = aws_ssm_parameter.cloudwatch_agent_config.name
    install_complete = null_resource.install_cloudwatch_agent.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo ""
      echo "Waiting 10 seconds for CloudWatch Agent installation to settle..."
      sleep 10
      
      echo ""
      echo "Configuring CloudWatch Agent on instance ${var.instance_id}..."
      
      # Create configuration and startup commands
      # Step 1: Download config from SSM Parameter
      # Step 2: Configure the agent
      # Step 3: Explicitly start the service
      # Step 4: Enable the service for auto-start
      # Step 5: Verify it's running
      CONFIG_SCRIPT="aws ssm get-parameter --name '${aws_ssm_parameter.cloudwatch_agent_config.name}' --region ${var.aws_region} --query 'Parameter.Value' --output text > /tmp/amazon-cloudwatch-agent.json && sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/tmp/amazon-cloudwatch-agent.json && sudo systemctl start amazon-cloudwatch-agent && sudo systemctl enable amazon-cloudwatch-agent && sleep 3 && sudo systemctl is-active amazon-cloudwatch-agent && echo 'CloudWatch Agent is running'"
      
      # Send configuration command via SSM
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${var.instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"$CONFIG_SCRIPT\"]" \
        --region ${var.aws_region} \
        --output text \
        --query 'Command.CommandId')
      
      echo "Command ID: $COMMAND_ID"
      echo "Waiting for configuration to complete (this may take 1-2 minutes)..."
      
      # Wait for command to complete
      for i in {1..20}; do
        STATUS=$(aws ssm get-command-invocation \
          --command-id "$COMMAND_ID" \
          --instance-id "${var.instance_id}" \
          --region ${var.aws_region} \
          --query 'Status' \
          --output text 2>/dev/null || echo "InProgress")
        
        if [ "$STATUS" == "Success" ]; then
          echo ""
          echo "✅ CloudWatch Agent configured and started successfully!"
          echo ""
          echo "Output:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text
          echo ""
          echo "Verifying agent status..."
          # Verify agent is actually running
          VERIFY_CMD=$(aws ssm send-command \
            --instance-ids "${var.instance_id}" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["sudo systemctl is-active amazon-cloudwatch-agent && sudo systemctl is-enabled amazon-cloudwatch-agent && ls -la /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log 2>/dev/null && echo \"Log file exists\" || echo \"Log file will be created when agent starts\""]' \
            --region ${var.aws_region} \
            --output text \
            --query 'Command.CommandId')
          
          sleep 5
          VERIFY_OUTPUT=$(aws ssm get-command-invocation \
            --command-id "$VERIFY_CMD" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null || echo "")
          
          if [ ! -z "$VERIFY_OUTPUT" ]; then
            echo "$VERIFY_OUTPUT"
          fi
          break
        elif [ "$STATUS" == "Failed" ]; then
          echo ""
          echo "❌ Configuration failed!"
          echo "Standard Output:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardOutputContent' \
            --output text
          echo ""
          echo "Standard Error:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "${var.instance_id}" \
            --region ${var.aws_region} \
            --query 'StandardErrorContent' \
            --output text
          exit 1
        else
          echo -n "."
          sleep 6
        fi
      done
      
      if [ "$STATUS" != "Success" ]; then
        echo ""
        echo "⚠️  Configuration timed out. Status: $STATUS"
        echo "Check command status manually:"
        echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id ${var.instance_id} --region ${var.aws_region}"
      fi
    EOT
  }

  depends_on = [
    aws_ssm_parameter.cloudwatch_agent_config,
    null_resource.install_cloudwatch_agent
  ]
}

