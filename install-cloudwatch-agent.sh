#!/bin/bash

# CloudWatch Agent Installation and Configuration Script
# This script installs and configures CloudWatch Agent for EC2 instance
# Required for disk and memory monitoring alarms

set -e

echo "=========================================="
echo "CloudWatch Agent Installation Script"
echo "=========================================="

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Cannot detect OS. Exiting."
    exit 1
fi

echo "Detected OS: $OS $VER"

# Check if running on Amazon Linux or RHEL/CentOS
if [[ "$OS" == "amzn" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    echo "Installing CloudWatch Agent for Amazon Linux/RHEL/CentOS..."
    
    # Download and install CloudWatch Agent
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    sudo rpm -U ./amazon-cloudwatch-agent.rpm
    
    echo "CloudWatch Agent installed successfully!"
    
elif [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    echo "Installing CloudWatch Agent for Ubuntu/Debian..."
    
    # Download and install CloudWatch Agent
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
    
    echo "CloudWatch Agent installed successfully!"
else
    echo "Unsupported OS: $OS"
    echo "Please install CloudWatch Agent manually from:"
    echo "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-commandline-fleethost.html"
    exit 1
fi

# Check if config file exists
if [ ! -f "cloudwatch-agent-config.json" ]; then
    echo "ERROR: cloudwatch-agent-config.json not found!"
    echo "Please ensure the config file is in the current directory."
    exit 1
fi

# Copy config file to CloudWatch Agent directory
echo "Copying configuration file..."
sudo cp cloudwatch-agent-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Start CloudWatch Agent
echo "Starting CloudWatch Agent..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Check status
echo ""
echo "=========================================="
echo "CloudWatch Agent Status"
echo "=========================================="
sudo systemctl status amazon-cloudwatch-agent

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo "CloudWatch Agent is now running and collecting metrics."
echo ""
echo "To check status: sudo systemctl status amazon-cloudwatch-agent"
echo "To view logs: sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
echo ""
echo "Note: It may take a few minutes for metrics to appear in CloudWatch."
echo "Your disk and memory alarms should start receiving data within 5-10 minutes."

