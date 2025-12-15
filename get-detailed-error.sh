#!/bin/bash

# Get more detailed error information

COMMAND_ID="e8bfd056-8703-4307-b26d-ff586a8c1ba1"
INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "Getting full command details..."
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region $REGION \
  --output json | jq '.'

echo ""
echo "Checking CloudWatch Logs (if enabled)..."
aws logs tail /aws/ssm/AWS-RunShellScript \
  --region $REGION \
  --since 30m 2>/dev/null | tail -50 || echo "CloudWatch Logs not available"

echo ""
echo "Trying to get command output from list-command-invocations..."
aws ssm list-command-invocations \
  --command-id "$COMMAND_ID" \
  --region $REGION \
  --output json | jq '.CommandInvocations[0] | {
    Status: .Status,
    StatusDetails: .StatusDetails,
    StandardOutput: .StandardOutputContent,
    StandardError: .StandardErrorContent,
    ResponseCode: .ResponseCode
  }'

