#!/bin/bash

# Quick script to check SSM Association execution status

ASSOCIATION_ID="ef122688-0300-4ec8-a589-1744e12795d4"
REGION="ap-south-1"

echo "Checking SSM Association Execution Status..."
echo "Association ID: $ASSOCIATION_ID"
echo ""

# Get latest execution
EXECUTION=$(aws ssm describe-association-executions \
  --association-id "$ASSOCIATION_ID" \
  --region $REGION \
  --max-results 1 \
  --query 'AssociationExecutions[0]' \
  --output json 2>/dev/null)

if [ "$EXECUTION" != "null" ] && [ ! -z "$EXECUTION" ]; then
  EXEC_ID=$(echo $EXECUTION | jq -r '.ExecutionId')
  STATUS=$(echo $EXECUTION | jq -r '.Status')
  DATE=$(echo $EXECUTION | jq -r '.ExecutionDate')
  
  echo "Latest Execution:"
  echo "  Execution ID: $EXEC_ID"
  echo "  Status: $STATUS"
  echo "  Date: $DATE"
  echo ""
  
  if [ "$STATUS" == "Success" ]; then
    echo "✅ SSM Association executed successfully!"
    echo ""
    echo "Checking execution details..."
    aws ssm describe-association-execution-targets \
      --association-id "$ASSOCIATION_ID" \
      --execution-id "$EXEC_ID" \
      --region $REGION \
      --query 'AssociationExecutionTargets[0].[Status,DetailedStatus]' \
      --output table
  elif [ "$STATUS" == "Failed" ]; then
    echo "❌ SSM Association failed!"
    echo ""
    echo "Error details:"
    aws ssm describe-association-execution-targets \
      --association-id "$ASSOCIATION_ID" \
      --execution-id "$EXEC_ID" \
      --region $REGION \
      --output json | jq '.AssociationExecutionTargets[0]'
  else
    echo "⏳ Status: $STATUS (may still be running)"
  fi
else
  echo "⚠️  No execution found yet."
  echo "The SSM Association may execute automatically, or you may need to trigger it manually."
  echo ""
  echo "To trigger manually:"
  echo "aws ssm start-associations-once --association-ids $ASSOCIATION_ID --region $REGION"
fi

