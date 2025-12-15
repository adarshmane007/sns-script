#!/bin/bash

# Investigate why SSM Association configuration is failing

ASSOC_ID="ef122688-0300-4ec8-a589-1744e12795d4"
EXEC_ID="e70c378d-3579-4d3c-98ef-35e4e596e723"
INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "Investigating SSM Association Configuration Failure"
echo "=========================================="
echo ""

echo "1. Getting Execution Target Details..."
EXEC_TARGET=$(aws ssm describe-association-execution-targets \
  --association-id "$ASSOC_ID" \
  --execution-id "$EXEC_ID" \
  --region $REGION \
  --output json)

echo "$EXEC_TARGET" | jq '.'

COMMAND_ID=$(echo $EXEC_TARGET | jq -r '.AssociationExecutionTargets[0].OutputSource.OutputSourceId')
echo ""
echo "Command ID: $COMMAND_ID"
echo ""

echo "2. Getting Command Invocation Details..."
COMMAND_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region $REGION \
  --output json 2>/dev/null)

if [ $? -eq 0 ]; then
  echo "Command Status: $(echo $COMMAND_OUTPUT | jq -r '.Status')"
  echo "Response Code: $(echo $COMMAND_OUTPUT | jq -r '.ResponseCode')"
  echo ""
  echo "Standard Output:"
  echo "$COMMAND_OUTPUT" | jq -r '.StandardOutputContent' | head -100
  echo ""
  echo "Standard Error:"
  echo "$COMMAND_OUTPUT" | jq -r '.StandardErrorContent' | head -100
else
  echo "Could not retrieve command invocation."
  echo ""
  echo "3. Listing Recent Commands..."
  aws ssm list-command-invocations \
    --instance-id "$INSTANCE_ID" \
    --region $REGION \
    --max-results 3 \
    --output json | jq '.CommandInvocations[] | {
      CommandId: .CommandId,
      Status: .Status,
      DocumentName: .DocumentName,
      StandardOutput: .StandardOutputContent,
      StandardError: .StandardErrorContent
    }'
fi

echo ""
echo "4. Checking SSM Parameter (Config File)..."
PARAM_NAME="/AmazonCloudWatch-Config/monitored-instance/amazon-cloudwatch-agent.json"
PARAM_VALUE=$(aws ssm get-parameter \
  --name "$PARAM_NAME" \
  --region $REGION \
  --query 'Parameter.Value' \
  --output text 2>/dev/null)

if [ $? -eq 0 ]; then
  echo "✅ SSM Parameter exists"
  echo "Parameter value (first 500 chars):"
  echo "$PARAM_VALUE" | head -c 500
  echo "..."
else
  echo "❌ SSM Parameter NOT FOUND!"
fi

echo ""
echo "5. Checking CloudWatch Agent Installation on Target Server..."
echo "   Run on target server:"
echo "   ls -la /opt/aws/amazon-cloudwatch-agent/bin/"
echo "   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent -version"

