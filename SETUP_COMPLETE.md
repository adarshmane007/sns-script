# Complete Setup Guide - CloudWatch Agent with Terraform

## ✅ What This Setup Does

This Terraform configuration automatically:
1. ✅ Creates IAM role with SSM and CloudWatch permissions
2. ✅ Attaches IAM role to your EC2 instance
3. ✅ Creates CloudWatch Agent configuration in SSM Parameter Store
4. ✅ Creates SSM Association to install CloudWatch Agent
5. ✅ Triggers SSM Association execution
6. ✅ Creates 3 CloudWatch Alarms (CPU, Disk, Memory)
7. ✅ Creates SNS Topic and Email Subscription

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- EC2 instance ID to monitor

### Steps

1. **Clone/Pull the repository:**
```bash
git clone https://github.com/adarshmane007/sns-script.git
cd sns-script
```

2. **Configure variables in `terraform.tfvars`:**
```hcl
environment            = "dev"
cloudwatch_alarm_email = "your-email@example.com"
instance_id            = "i-xxxxxxxxxxxxx"
instance_name          = "monitored-instance"
device_name            = "nvme0n1p1"  # or xvda, sda1, etc.
```

3. **Initialize Terraform:**
```bash
terraform init
```

4. **Review the plan:**
```bash
terraform plan
```

5. **Apply the configuration:**
```bash
terraform apply
```

6. **Wait for CloudWatch Agent installation (5-10 minutes):**
   - SSM Association will execute automatically
   - CloudWatch Agent will be installed and configured
   - Metrics will start flowing

## 📋 Verification Steps

### 1. Verify IAM Role Attachment
```bash
aws ec2 describe-instances \
  --instance-ids i-020be26a823f801d5 \
  --region ap-south-1 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
```

Should show: `arn:aws:iam::ACCOUNT_ID:instance-profile/monitored-instance-cloudwatch-profile`

### 2. Check SSM Association Status
```bash
terraform output cloudwatch_agent_ssm_association_id
ASSOC_ID=$(terraform output -raw cloudwatch_agent_ssm_association_id)

aws ssm describe-association-executions \
  --association-id $ASSOC_ID \
  --region ap-south-1 \
  --max-results 1
```

### 3. SSH into Instance and Verify CloudWatch Agent
```bash
# SSH into your instance
ssh ec2-user@<instance-ip>

# Check CloudWatch Agent status
sudo systemctl status amazon-cloudwatch-agent

# Check CloudWatch Agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

### 4. Check CloudWatch Metrics (after 5-10 minutes)
```bash
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=i-020be26a823f801d5 \
  --region ap-south-1
```

### 5. Check Alarm Status in AWS Console
- Go to CloudWatch → Alarms
- All 3 alarms should show "OK" or have data (not "Insufficient data")

## 🔧 Troubleshooting

### Issue: SSM Association Failed

**Check execution details:**
```bash
ASSOC_ID=$(terraform output -raw cloudwatch_agent_ssm_association_id)
EXEC_ID=$(aws ssm describe-association-executions \
  --association-id $ASSOC_ID \
  --region ap-south-1 \
  --max-results 1 \
  --query 'AssociationExecutions[0].ExecutionId' \
  --output text)

aws ssm describe-association-execution-targets \
  --association-id $ASSOC_ID \
  --execution-id $EXEC_ID \
  --region ap-south-1
```

**Manually trigger association:**
```bash
ASSOC_ID=$(terraform output -raw cloudwatch_agent_ssm_association_id)
aws ssm start-associations-once \
  --association-ids $ASSOC_ID \
  --region ap-south-1
```

### Issue: CloudWatch Agent Not Installed

**SSH into instance and check:**
```bash
# Check if agent exists
ls -la /opt/aws/amazon-cloudwatch-agent/bin/

# Check SSM Agent (required for SSM to work)
sudo systemctl status amazon-ssm-agent

# If SSM Agent not running:
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
```

**Manually install CloudWatch Agent (if SSM fails):**
```bash
# On Amazon Linux 2
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# Get config from SSM
CONFIG_PARAM=$(terraform output -raw cloudwatch_agent_config_parameter)
aws ssm get-parameter --name $CONFIG_PARAM --region ap-south-1 --query 'Parameter.Value' --output text > /tmp/config.json

# Start agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/tmp/config.json \
  -s
```

### Issue: No CloudWatch Metrics

**Wait 5-10 minutes** - Metrics collection interval is 60 seconds, but CloudWatch may take time to process.

**Verify agent is running:**
```bash
sudo systemctl status amazon-cloudwatch-agent
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

**Check IAM permissions:**
```bash
# On the instance, check if role is active
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Test CloudWatch permissions
aws cloudwatch put-metric-data \
  --namespace CWAgent \
  --metric-name TestMetric \
  --value 1 \
  --region ap-south-1
```

### Issue: Wrong Device Name

**Find your device name:**
```bash
# On the instance
df -h
lsblk

# Check CloudWatch metrics
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --region ap-south-1
```

**Update terraform.tfvars:**
```hcl
device_name = "xvda"  # or whatever your device is
```

**Reapply:**
```bash
terraform apply
```

## 📊 Expected Results

After successful setup:

1. **IAM Role:** Attached to instance ✅
2. **SSM Association:** Executed successfully ✅
3. **CloudWatch Agent:** Installed and running ✅
4. **CloudWatch Metrics:** Appearing in CWAgent namespace ✅
5. **Alarms:** All 3 alarms showing "OK" or data ✅
6. **SNS Email:** Confirmation email sent (check inbox) ✅

## 📁 File Structure

```
.
├── alarm.tf                    # CloudWatch alarms (CPU, Disk, Memory)
├── cloudwatch-agent.tf        # CloudWatch Agent installation via SSM
├── iam.tf                      # IAM role, policies, instance profile
├── instances.tf               # Instance data source and local map
├── outputs.tf                 # Terraform outputs
├── provider.tf               # AWS provider configuration
├── sns.tf                     # SNS topic and email subscription
├── variables.tf               # Variable definitions
├── terraform.tfvars          # Your configuration values
└── verify-cloudwatch-agent.sh # Verification script
```

## 🔄 Updating Configuration

To update CloudWatch Agent configuration:

1. Edit `cloudwatch-agent.tf` (the `aws_ssm_parameter` resource)
2. Run `terraform apply`
3. The SSM Association will automatically update the agent

## 🗑️ Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note:** This will:
- Delete CloudWatch Alarms
- Delete SNS Topic and Subscription
- Delete IAM Role and Instance Profile (disassociates from instance)
- Delete SSM Parameter and Association
- **NOT** delete your EC2 instance

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review CloudWatch Agent logs on the instance
3. Check SSM Association execution details
4. Verify IAM role permissions

