#!/bin/bash

# Check recent metric datapoints and alarm status

INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "Checking Recent Metrics and Alarm Status"
echo "=========================================="
echo ""

echo "1. Getting recent disk_used_percent datapoints (last 15 minutes)..."
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=device,Value=nvme0n1p1 Name=path,Value=/ \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region $REGION \
  --output table

echo ""
echo "2. Getting recent mem_used_percent datapoints (last 15 minutes)..."
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region $REGION \
  --output table

echo ""
echo "3. Checking Alarm States..."
echo ""

# Check disk alarm
echo "Disk Usage Alarm:"
aws cloudwatch describe-alarms \
  --alarm-names "monitored-instance-disk-usage-high" \
  --region $REGION \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason,StateUpdatedTimestamp]' \
  --output table

echo ""
echo "Memory Usage Alarm:"
aws cloudwatch describe-alarms \
  --alarm-names "monitored-instance-memory-usage-high" \
  --region $REGION \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason,StateUpdatedTimestamp]' \
  --output table

echo ""
echo "CPU Utilization Alarm:"
aws cloudwatch describe-alarms \
  --alarm-names "monitored-instance-cpu-utilization-high" \
  --region $REGION \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason,StateUpdatedTimestamp]' \
  --output table

echo ""
echo "4. Listing all CWAgent metrics for this instance..."
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'Metrics[*].[MetricName,Dimensions[?Key==`device`].Value | [0],Dimensions[?Key==`path`].Value | [0]]' \
  --output table

