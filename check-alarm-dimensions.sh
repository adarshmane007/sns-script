#!/bin/bash

# Check alarm dimensions vs actual metrics dimensions

INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "Checking Alarm Dimensions vs Metric Dimensions"
echo "=========================================="
echo ""

echo "1. Disk Alarm Configuration:"
aws cloudwatch describe-alarms \
  --alarm-names "monitored-instance-disk-usage-high" \
  --region $REGION \
  --query 'MetricAlarms[0].Dimensions' \
  --output json | jq '.'

echo ""
echo "2. Actual Disk Metrics Dimensions:"
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'Metrics[*].Dimensions' \
  --output json | jq '.'

echo ""
echo "3. Memory Alarm Configuration:"
aws cloudwatch describe-alarms \
  --alarm-names "monitored-instance-memory-usage-high" \
  --region $REGION \
  --query 'MetricAlarms[0].Dimensions' \
  --output json | jq '.'

echo ""
echo "4. Actual Memory Metrics Dimensions:"
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'Metrics[*].Dimensions' \
  --output json | jq '.'

echo ""
echo "5. Checking if alarms can find matching metrics..."
echo ""

# Check if disk alarm can find metrics with its dimensions
DISK_ALARM_DIMS=$(aws cloudwatch describe-alarms \
  --alarm-names "monitored-instance-disk-usage-high" \
  --region $REGION \
  --query 'MetricAlarms[0].Dimensions' \
  --output json)

DEVICE=$(echo $DISK_ALARM_DIMS | jq -r '.[] | select(.Name=="device") | .Value')
PATH_VAL=$(echo $DISK_ALARM_DIMS | jq -r '.[] | select(.Name=="path") | .Value')

echo "Disk Alarm is looking for:"
echo "  InstanceId: $INSTANCE_ID"
echo "  device: $DEVICE"
echo "  path: $PATH_VAL"
echo ""

echo "Checking if matching metrics exist..."
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=device,Value=$DEVICE Name=path,Value=$PATH_VAL \
  --region $REGION \
  --query 'length(Metrics)' \
  --output text

echo ""
echo "6. Getting recent datapoints with alarm dimensions..."
if [ ! -z "$DEVICE" ] && [ "$DEVICE" != "null" ]; then
  echo "Recent disk_used_percent datapoints (last 20 minutes):"
  aws cloudwatch get-metric-statistics \
    --namespace CWAgent \
    --metric-name disk_used_percent \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=device,Value=$DEVICE Name=path,Value=$PATH_VAL \
    --start-time $(date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --output table
fi

echo ""
echo "Recent mem_used_percent datapoints (last 20 minutes):"
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region $REGION \
  --output table

