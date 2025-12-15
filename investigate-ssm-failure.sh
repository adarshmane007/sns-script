#!/bin/bash

# Comprehensive investigation script for SSM Association failure
# Run this on the command server

ASSOC_ID="ef122688-0300-4ec8-a589-1744e12795d4"
EXEC_ID="1644e899-b9f6-45b6-a171-adfb75073195"
INSTANCE_ID="i-020be26a823f801d5"
REGION="ap-south-1"

echo "=========================================="
echo "SSM Association Failure Investigation"
echo "=========================================="
echo ""

echo "1. Getting Execution Target Details..."
EXEC_TARGET=$(aws ssm describe-association-execution-targets \
  --association-id "$ASSOC_ID" \
  --execution-id "$EXEC_ID" \
  --region $REGION \
  --output json)

COMMAND_ID=$(echo $EXEC_TARGET | jq -r '.AssociationExecutionTargets[0].OutputSource.OutputSourceId')
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
  echo "$COMMAND_OUTPUT" | jq -r '.StandardOutputContent' | head -50
  echo ""
  echo "Standard Error:"
  echo "$COMMAND_OUTPUT" | jq -r '.StandardErrorContent' | head -50
else
  echo "Could not retrieve command invocation. Trying alternative method..."
  echo ""
  
  echo "3. Listing Recent Commands for Instance..."
  aws ssm list-command-invocations \
    --instance-id "$INSTANCE_ID" \
    --region $REGION \
    --max-results 3 \
    --output json | jq '.CommandInvocations[] | {
      CommandId: .CommandId,
      Status: .Status,
      StatusDetails: .StatusDetails,
      StandardOutput: .StandardOutputContent,
      StandardError: .StandardErrorContent
    }'
fi

echo ""
echo "4. Checking SSM Association Configuration..."
ASSOC_CONFIG=$(aws ssm describe-association \
  --association-id "$ASSOC_ID" \
  --region $REGION \
  --output json)

echo "Association Name: $(echo $ASSOC_CONFIG | jq -r '.Association.Name')"
echo "Association Parameters:"
echo $ASSOC_CONFIG | jq '.Association.Parameters'

echo ""
echo "5. Checking SSM Parameter (CloudWatch Agent Config)..."
PARAM_NAME=$(echo $ASSOC_CONFIG | jq -r '.Association.Parameters.optionalConfigurationLocation')
echo "Parameter Name: $PARAM_NAME"

if [ "$PARAM_NAME" != "null" ] && [ ! -z "$PARAM_NAME" ]; then
  PARAM_EXISTS=$(aws ssm get-parameter \
    --name "$PARAM_NAME" \
    --region $REGION \
    --query 'Parameter.Name' \
    --output text 2>/dev/null || echo "NOT_FOUND")
  
  if [ "$PARAM_EXISTS" != "NOT_FOUND" ]; then
    echo "✅ SSM Parameter exists"
    echo "Parameter Type: $(aws ssm get-parameter --name "$PARAM_NAME" --region $REGION --query 'Parameter.Type' --output text)"
  else
    echo "❌ SSM Parameter NOT FOUND: $PARAM_NAME"
  fi
fi

echo ""
echo "6. Checking Instance IAM Role..."
IAM_PROFILE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region $REGION \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text)

if [ "$IAM_PROFILE" != "None" ] && [ ! -z "$IAM_PROFILE" ]; then
  echo "✅ IAM Instance Profile: $IAM_PROFILE"
else
  echo "❌ No IAM Instance Profile attached!"
fi

echo ""
echo "7. Checking SSM Agent Status..."
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region $REGION \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "UNABLE_TO_CHECK")

if [ "$SSM_STATUS" == "Online" ]; then
  echo "✅ SSM Agent is Online"
elif [ "$SSM_STATUS" == "UNABLE_TO_CHECK" ]; then
  echo "⚠️  Cannot check SSM Agent status (may need IAM permissions)"
else
  echo "❌ SSM Agent Status: $SSM_STATUS"
fi

echo ""
echo "=========================================="
echo "Investigation Complete"
echo "=========================================="

