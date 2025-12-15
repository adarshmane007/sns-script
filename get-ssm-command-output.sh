#!/bin/bash

# Get the actual command output from failed SSM execution

ASSOCIATION_ID="ef122688-0300-4ec8-a589-1744e12795d4"
EXECUTION_ID="566487e7-b544-45fb-804b-6e6332ef9458"
INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "Getting command ID from execution targets..."
COMMAND_ID=$(aws ssm describe-association-execution-targets \
  --association-id "$ASSOCIATION_ID" \
  --execution-id "$EXECUTION_ID" \
  --region $REGION \
  --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' \
  --output text 2>/dev/null)

if [ "$COMMAND_ID" != "None" ] && [ ! -z "$COMMAND_ID" ]; then
  echo "Command ID: $COMMAND_ID"
  echo ""
  echo "Getting command invocation details..."
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region $REGION \
    --output json 2>/dev/null | jq '.'
else
  echo "Could not retrieve command ID. Trying alternative method..."
  
  # List recent commands for this instance
  echo ""
  echo "Recent commands for instance:"
  aws ssm list-command-invocations \
    --instance-id "$INSTANCE_ID" \
    --region $REGION \
    --max-results 5 \
    --output json | jq '.CommandInvocations[] | {CommandId, Status, StatusDetails, StandardOutputContent, StandardErrorContent}'
fi

