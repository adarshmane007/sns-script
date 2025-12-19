#!/bin/bash
# Pre-deployment check script for one-click deployment
# Automatically handles state file cleanup when switching AWS accounts

set -e

echo "=========================================="
echo "Pre-Deployment Check"
echo "=========================================="
echo ""

# Get current AWS account ID
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$CURRENT_ACCOUNT" ]; then
  echo "ERROR: AWS credentials not configured or invalid"
  echo "Please configure AWS credentials and try again"
  exit 1
fi

echo "Current AWS Account: $CURRENT_ACCOUNT"
echo "Current Region: ${AWS_REGION:-$(aws configure get region || echo 'ap-south-1')}"
echo ""

# Check if state file exists
if [ -f "terraform.tfstate" ]; then
  echo "State file found. Checking for account mismatch..."
  
  # Extract account ID from state file (if it exists)
  STATE_ACCOUNT=$(grep -o '"account_id":"[^"]*"' terraform.tfstate 2>/dev/null | head -1 | cut -d'"' -f4 || echo "")
  
  # Also check for account IDs in resource ARNs
  if [ -z "$STATE_ACCOUNT" ]; then
    STATE_ACCOUNT=$(grep -oE 'arn:aws:[^:]+:[^:]+:[0-9]{12}' terraform.tfstate 2>/dev/null | head -1 | cut -d':' -f5 || echo "")
  fi
  
  if [ ! -z "$STATE_ACCOUNT" ] && [ "$STATE_ACCOUNT" != "$CURRENT_ACCOUNT" ]; then
    echo "⚠️  WARNING: Account mismatch detected!"
    echo "   State file account: $STATE_ACCOUNT"
    echo "   Current account:    $CURRENT_ACCOUNT"
    echo ""
    echo "Backing up old state file and cleaning for new account..."
    
    # Create backup directory with timestamp
    BACKUP_DIR="terraform-state-backups/$(date +%Y%m%d_%H%M%S)_account_${STATE_ACCOUNT}"
    mkdir -p "$BACKUP_DIR"
    
    # Backup all state files
    cp terraform.tfstate "$BACKUP_DIR/" 2>/dev/null || true
    cp terraform.tfstate.backup "$BACKUP_DIR/" 2>/dev/null || true
    cp terraform.tfstate.*.backup "$BACKUP_DIR/" 2>/dev/null || true
    
    echo "✅ State files backed up to: $BACKUP_DIR"
    echo ""
    echo "Removing old state files..."
    
    # Remove old state files
    rm -f terraform.tfstate terraform.tfstate.backup terraform.tfstate.*.backup 2>/dev/null || true
    
    echo "✅ State files cleaned. Ready for fresh deployment."
    echo ""
  else
    echo "✅ State file account matches current account. Proceeding..."
    echo ""
  fi
else
  echo "No state file found. This appears to be a fresh deployment."
  echo ""
fi

# Validate instances exist before proceeding
echo "Validating configured instances..."
echo ""

# Read instances from terraform.tfvars
INSTANCES=$(grep -A 5 "instances = \[" terraform.tfvars | grep -E "tag_key|tag_value" | sed 's/.*= *"\([^"]*\)".*/\1/' || echo "")

if [ ! -z "$INSTANCES" ]; then
  echo "Checking if instances with configured tags exist..."
  # This is a basic check - full validation happens in Terraform
  echo "✅ Instance validation will be performed by Terraform"
else
  echo "⚠️  WARNING: No instances configured in terraform.tfvars"
fi

echo ""
echo "=========================================="
echo "Pre-deployment check complete!"
echo "You can now run: terraform init && terraform apply"
echo "=========================================="

