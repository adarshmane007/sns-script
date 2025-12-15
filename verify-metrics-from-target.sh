#!/bin/bash

# Verify CloudWatch Agent is sending metrics from target server
# Run this ON the target server (i-020be26a823f801d5)

INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "Verifying CloudWatch Metrics from Target Server"
echo "=========================================="
echo ""

echo "1. Checking CloudWatch Agent Status..."
sudo systemctl status amazon-cloudwatch-agent --no-pager | head -10

echo ""
echo "2. Checking CloudWatch Agent Logs (recent activity)..."
sudo tail -20 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log | grep -E "(PutMetricData|publish|metric)" || echo "No recent metric publishing activity in logs"

echo ""
echo "3. Checking if metrics are being published to CloudWatch..."
echo "   (This checks if metrics exist in CloudWatch for this instance)"
echo ""

# Check disk metrics
echo "Checking disk_used_percent metrics..."
DISK_METRICS=$(aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'length(Metrics)' \
  --output text 2>/dev/null || echo "0")

if [ "$DISK_METRICS" -gt 0 ]; then
  echo "✅ Disk metrics found: $DISK_METRICS metric(s)"
else
  echo "⏳ No disk metrics yet (may take 5-10 minutes to appear)"
fi

# Check memory metrics
echo ""
echo "Checking mem_used_percent metrics..."
MEM_METRICS=$(aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'length(Metrics)' \
  --output text 2>/dev/null || echo "0")

if [ "$MEM_METRICS" -gt 0 ]; then
  echo "✅ Memory metrics found: $MEM_METRICS metric(s)"
else
  echo "⏳ No memory metrics yet (may take 5-10 minutes to appear)"
fi

# Check CPU metrics (from AWS/EC2 namespace)
echo ""
echo "Checking CPUUtilization metrics (AWS/EC2 namespace)..."
CPU_METRICS=$(aws cloudwatch list-metrics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'length(Metrics)' \
  --output text 2>/dev/null || echo "0")

if [ "$CPU_METRICS" -gt 0 ]; then
  echo "✅ CPU metrics found: $CPU_METRICS metric(s)"
else
  echo "⚠️  No CPU metrics found"
fi

echo ""
echo "4. Getting recent metric data points (if available)..."
echo ""

# Try to get recent disk metric data
if [ "$DISK_METRICS" -gt 0 ]; then
  echo "Recent disk_used_percent data:"
  aws cloudwatch get-metric-statistics \
    --namespace CWAgent \
    --metric-name disk_used_percent \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[*].[Timestamp,Average]' \
    --output table 2>/dev/null || echo "No recent datapoints"
fi

echo ""
echo "5. Checking CloudWatch Agent configuration..."
sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json | jq '.metrics.metrics_collected' 2>/dev/null || echo "Config file not readable or jq not installed"

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo ""
echo "Expected Metrics:"
echo "  - CPU: AWS/EC2 namespace (built-in)"
echo "  - Disk: CWAgent namespace (from CloudWatch Agent)"
echo "  - Memory: CWAgent namespace (from CloudWatch Agent)"
echo ""
echo "Note: Metrics may take 5-10 minutes to appear in CloudWatch"
echo "      after the agent starts sending data."

