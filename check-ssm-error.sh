#!/bin/bash

# Check detailed SSM Association execution error

ASSOCIATION_ID="ef122688-0300-4ec8-a589-1744e12795d4"
EXECUTION_ID="566487e7-b544-45fb-804b-6e6332ef9458"
REGION="ap-south-1"

echo "Checking SSM Association Execution Error Details..."
echo "Association ID: $ASSOCIATION_ID"
echo "Execution ID: $EXECUTION_ID"
echo ""

# Get detailed execution targets (this shows the actual error)
echo "Execution Target Details:"
aws ssm describe-association-execution-targets \
  --association-id "$ASSOCIATION_ID" \
  --execution-id "$EXECUTION_ID" \
  --region $REGION \
  --output json | jq '.'

echo ""
echo "Getting command output..."
aws ssm get-command-invocation \
  --command-id $(aws ssm describe-association-execution-targets \
    --association-id "$ASSOCIATION_ID" \
    --execution-id "$EXECUTION_ID" \
    --region $REGION \
    --query 'AssociationExecutionTargets[0].OutputDetails.CommandId' \
    --output text) \
  --instance-id i-020be26a823f801d5 \
  --region $REGION \
  --output json 2>/dev/null | jq '.' || echo "Could not retrieve command invocation"

