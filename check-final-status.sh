#!/bin/bash

# Check final status of CloudWatch Agent setup

ASSOC_ID="ef122688-0300-4ec8-a589-1744e12795d4"
INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "CloudWatch Agent Final Status Check"
echo "=========================================="
echo ""

echo "1. Checking Latest SSM Association Execution..."
LATEST_EXEC=$(aws ssm describe-association-executions \
  --association-id "$ASSOC_ID" \
  --region $REGION \
  --max-results 1 \
  --output json)

EXEC_ID=$(echo $LATEST_EXEC | jq -r '.AssociationExecutions[0].ExecutionId')
STATUS=$(echo $LATEST_EXEC | jq -r '.AssociationExecutions[0].Status')
CREATED_TIME=$(echo $LATEST_EXEC | jq -r '.AssociationExecutions[0].CreatedTime')

echo "Execution ID: $EXEC_ID"
echo "Status: $STATUS"
echo "Created: $CREATED_TIME"
echo ""

if [ "$STATUS" == "Success" ]; then
  echo "✅ SSM Association executed successfully!"
elif [ "$STATUS" == "Failed" ]; then
  echo "❌ SSM Association failed!"
  echo ""
  echo "Getting error details..."
  aws ssm describe-association-execution-targets \
    --association-id "$ASSOC_ID" \
    --execution-id "$EXEC_ID" \
    --region $REGION \
    --output json | jq '.'
else
  echo "⏳ Status: $STATUS (may still be running)"
fi

echo ""
echo "2. Checking CloudWatch Agent Status on Target Server..."
echo "   (SSH into instance $INSTANCE_ID and run):"
echo "   sudo systemctl status amazon-cloudwatch-agent"
echo ""

echo "3. If agent is not running, manually start it:"
echo "   sudo systemctl start amazon-cloudwatch-agent"
echo "   sudo systemctl enable amazon-cloudwatch-agent"
echo ""

echo "4. Check CloudWatch Metrics (wait 5-10 minutes after agent starts):"
echo "   aws cloudwatch list-metrics \\"
echo "     --namespace CWAgent \\"
echo "     --metric-name disk_used_percent \\"
echo "     --dimensions Name=InstanceId,Value=$INSTANCE_ID \\"
echo "     --region $REGION"
echo ""

