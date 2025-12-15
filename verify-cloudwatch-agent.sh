#!/bin/bash

# Verification script to check CloudWatch Agent installation status
# Run this on the server where you ran terraform apply

INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "CloudWatch Agent Installation Verification"
echo "=========================================="
echo ""

echo "1. Checking IAM Role Attachment..."
IAM_PROFILE=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text 2>/dev/null || echo "None")

if [ "$IAM_PROFILE" != "None" ] && [ ! -z "$IAM_PROFILE" ]; then
  echo "✅ IAM Instance Profile: $IAM_PROFILE"
else
  echo "❌ ERROR: No IAM Instance Profile attached!"
  echo "   The instance needs an IAM role for SSM and CloudWatch to work."
  exit 1
fi

echo ""
echo "2. Checking SSM Association Status..."
ASSOCIATION_ID=$(aws ssm list-associations \
  --association-filter-list key=InstanceId,value=$INSTANCE_ID \
  --region $REGION \
  --query 'Associations[?Name==`AmazonCloudWatch-ManageAgent`].AssociationId' \
  --output text 2>/dev/null || echo "None")

if [ "$ASSOCIATION_ID" != "None" ] && [ ! -z "$ASSOCIATION_ID" ]; then
  echo "✅ SSM Association ID: $ASSOCIATION_ID"
  
  # Get association execution details
  echo ""
  echo "3. Checking SSM Association Execution Status..."
  EXECUTION_STATUS=$(aws ssm describe-association-executions \
    --association-id "$ASSOCIATION_ID" \
    --region $REGION \
    --max-results 1 \
    --query 'AssociationExecutions[0].[ExecutionId,Status,ExecutionDate]' \
    --output text 2>/dev/null || echo "None None None")
  
  if [ "$EXECUTION_STATUS" != "None None None" ]; then
    EXEC_ID=$(echo $EXECUTION_STATUS | awk '{print $1}')
    STATUS=$(echo $EXECUTION_STATUS | awk '{print $2}')
    DATE=$(echo $EXECUTION_STATUS | awk '{print $3}')
    echo "   Execution ID: $EXEC_ID"
    echo "   Status: $STATUS"
    echo "   Date: $DATE"
    
    if [ "$STATUS" == "Success" ]; then
      echo "   ✅ SSM Association executed successfully!"
    elif [ "$STATUS" == "Failed" ]; then
      echo "   ❌ SSM Association failed!"
      echo "   Checking execution details..."
      aws ssm describe-association-execution-targets \
        --association-id "$ASSOCIATION_ID" \
        --execution-id "$EXEC_ID" \
        --region $REGION \
        --query 'AssociationExecutionTargets[0].[Status,DetailedStatus,OutputDetails]' \
        --output json
    else
      echo "   ⚠️  SSM Association status: $STATUS"
    fi
  else
    echo "   ⚠️  No execution found yet. SSM Association may still be running."
  fi
else
  echo "❌ ERROR: SSM Association not found!"
  echo "   Run 'terraform apply' to create the association."
fi

echo ""
echo "4. Checking SSM Agent Status on Target Instance..."
echo "   (This requires SSM access to the instance)"
INSTANCE_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region $REGION \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "None")

if [ "$INSTANCE_STATUS" == "Online" ]; then
  echo "   ✅ SSM Agent is Online"
elif [ "$INSTANCE_STATUS" == "None" ]; then
  echo "   ⚠️  Cannot check SSM Agent status (may need IAM permissions)"
else
  echo "   ❌ SSM Agent Status: $INSTANCE_STATUS"
  echo "   The instance may not be reachable via SSM."
fi

echo ""
echo "5. Checking CloudWatch Metrics..."
METRICS_COUNT=$(aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --region $REGION \
  --query 'length(Metrics)' \
  --output text 2>/dev/null || echo "0")

if [ "$METRICS_COUNT" -gt 0 ]; then
  echo "✅ CloudWatch metrics found: $METRICS_COUNT metric(s)"
  echo "   CloudWatch Agent is sending metrics!"
else
  echo "❌ No CloudWatch metrics found yet."
  echo "   This is normal if CloudWatch Agent was just installed."
  echo "   Wait 5-10 minutes for metrics to appear."
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "IAM Profile: $IAM_PROFILE"
echo "SSM Association: ${ASSOCIATION_ID:-Not found}"
echo ""
echo "Next Steps:"
echo "1. If IAM profile is missing, run: terraform apply"
echo "2. If SSM Association failed, check AWS Console → Systems Manager → Fleet Manager"
echo "3. SSH into instance $INSTANCE_ID and run: sudo systemctl status amazon-cloudwatch-agent"
echo "4. Wait 5-10 minutes after installation for metrics to appear"

