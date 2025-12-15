# CloudWatch Agent Setup Guide

## Problem
- **CPU Alarm**: ✅ Works (uses AWS/EC2 namespace - built-in metrics)
- **Disk Alarm**: ❌ Insufficient data (needs CloudWatch Agent)
- **Memory Alarm**: ❌ Insufficient data (needs CloudWatch Agent)

## Why This Happens
- CPU metrics come automatically from AWS EC2 service
- Disk and Memory metrics require CloudWatch Agent to be installed on the EC2 instance
- CloudWatch Agent sends custom metrics to the `CWAgent` namespace

## Prerequisites

### 1. IAM Role Permissions
Your EC2 instance needs an IAM role with CloudWatch permissions. The instance should have a policy that includes:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "ec2:DescribeVolumes",
        "ec2:DescribeTags",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:CreateLogStream",
        "logs:CreateLogGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

**To check if your instance has the right permissions:**
```bash
# Check IAM role attached to instance
aws sts get-caller-identity

# Test if you can put metrics
aws cloudwatch put-metric-data --namespace CWAgent --metric-name TestMetric --value 1 --region ap-south-1
```

## Installation Steps

### Option 1: Automated Installation (Recommended)

1. **SSH into your EC2 instance:**
   ```bash
   ssh ec2-user@<your-instance-ip>
   ```

2. **Download the installation script and config file:**
   ```bash
   # Download from your repo or copy the files
   wget https://raw.githubusercontent.com/adarshmane007/sns-script/main/install-cloudwatch-agent.sh
   wget https://raw.githubusercontent.com/adarshmane007/sns-script/main/cloudwatch-agent-config.json
   ```

3. **Make script executable and run:**
   ```bash
   chmod +x install-cloudwatch-agent.sh
   ./install-cloudwatch-agent.sh
   ```

### Option 2: Manual Installation

#### For Amazon Linux 2 / RHEL / CentOS:
```bash
# Download CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm

# Install
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# Copy config file
sudo cp cloudwatch-agent-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Start agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s
```

#### For Ubuntu / Debian:
```bash
# Download CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb

# Install
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

# Copy config file
sudo cp cloudwatch-agent-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Start agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s
```

## Verification

### 1. Check Agent Status
```bash
sudo systemctl status amazon-cloudwatch-agent
```

Expected output should show: `Active: active (running)`

### 2. Check Agent Logs
```bash
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

Look for any errors. You should see messages about collecting metrics.

### 3. Verify Metrics in CloudWatch (after 5-10 minutes)
```bash
# Check if disk metrics are being published
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --region ap-south-1 \
  --dimensions Name=InstanceId,Value=i-020be26a823f801d5

# Check if memory metrics are being published
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --region ap-south-1 \
  --dimensions Name=InstanceId,Value=i-020be26a823f801d5
```

### 4. Check Alarm Status in AWS Console
- Go to CloudWatch → Alarms
- Wait 5-10 minutes after installation
- Disk and Memory alarms should change from "Insufficient data" to "OK" or show actual data

## Troubleshooting

### Issue: Agent won't start
```bash
# Check logs
sudo cat /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Check IAM permissions
aws sts get-caller-identity
aws cloudwatch put-metric-data --namespace CWAgent --metric-name Test --value 1 --region ap-south-1
```

### Issue: Metrics not appearing
1. Wait 5-10 minutes (metrics collection interval is 60 seconds, but CloudWatch may take time to process)
2. Verify device name matches your instance:
   ```bash
   df -h
   lsblk
   ```
3. Update `device_name` in `terraform.tfvars` if needed, then run `terraform apply`

### Issue: Wrong device name
Find your actual device name:
```bash
# List block devices
lsblk

# Check mounted filesystems
df -h

# Check CloudWatch metrics to see what device is being reported
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --region ap-south-1
```

Then update `terraform.tfvars`:
```hcl
device_name = "xvda"  # or whatever your device is
```

Run `terraform apply` to update the alarm.

## Configuration File Details

The `cloudwatch-agent-config.json` file configures:
- **Metrics collection interval**: 60 seconds
- **Disk metrics**: Collects `used_percent` for all mounted disks
- **Memory metrics**: Collects `mem_used_percent`
- **CPU metrics**: Collects various CPU metrics (though we use AWS/EC2 for CPU alarm)
- **Dimensions**: Automatically adds InstanceId, ImageId, InstanceType

## After Installation

1. ✅ CloudWatch Agent installed and running
2. ⏳ Wait 5-10 minutes for metrics to start flowing
3. ✅ Check CloudWatch console - alarms should show data
4. ✅ Test by filling disk or memory to trigger alarms

## Useful Commands

```bash
# Start agent
sudo systemctl start amazon-cloudwatch-agent

# Stop agent
sudo systemctl stop amazon-cloudwatch-agent

# Restart agent
sudo systemctl restart amazon-cloudwatch-agent

# Check status
sudo systemctl status amazon-cloudwatch-agent

# View logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Reload configuration
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s
```

