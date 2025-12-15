#!/bin/bash

# Check detailed SSM Association configuration

ASSOC_ID="ef122688-0300-4ec8-a589-1744e12795d4"
REGION="ap-south-1"

echo "=========================================="
echo "Checking SSM Association Details"
echo "=========================================="
echo ""

echo "1. Full Association Details:"
aws ssm describe-association \
  --association-id "$ASSOC_ID" \
  --region $REGION \
  --output json | jq '.'

echo ""
echo "2. Checking if SSM Parameter exists:"
PARAM_NAME="/AmazonCloudWatch-Config/monitored-instance/amazon-cloudwatch-agent.json"
aws ssm get-parameter \
  --name "$PARAM_NAME" \
  --region $REGION \
  --output json 2>&1 | head -20

echo ""
echo "3. Checking Association Executions (latest 3):"
aws ssm describe-association-executions \
  --association-id "$ASSOC_ID" \
  --region $REGION \
  --max-results 3 \
  --output json | jq '.AssociationExecutions[] | {
    ExecutionId: .ExecutionId,
    Status: .Status,
    CreatedTime: .CreatedTime
  }'

