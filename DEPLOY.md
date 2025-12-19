# One-Click Deployment Guide

This setup supports one-click deployment across different AWS accounts with automatic state file management.

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.0)
3. Git Bash (for Windows) or Bash (for Linux/Mac)

## Quick Start

### For Windows (PowerShell):
```powershell
.\pre-deploy-check.ps1
terraform init
terraform apply -auto-approve
```

### For Linux/Mac (Bash):
```bash
chmod +x pre-deploy-check.sh
./pre-deploy-check.sh
terraform init
terraform apply -auto-approve
```

## What the Pre-Deployment Script Does

1. **Validates AWS Credentials**: Ensures AWS CLI is configured correctly
2. **Detects Account Mismatch**: Compares current AWS account with state file account
3. **Automatic State Cleanup**: If accounts don't match, automatically:
   - Backs up old state files to `terraform-state-backups/` directory
   - Removes old state files to prevent conflicts
   - Prepares for fresh deployment

## Configuration

Edit `terraform.tfvars` to configure instances:

```hcl
instances = [
  {
    name      = "instance-name-1"
    tag_key   = "Name"
    tag_value = "your-instance-tag-value"
    device    = "nvme0n1p1"  # Device name for disk metrics
  }
]
```

**Important Notes:**
- Use **tags** (tag_key and tag_value) to identify instances - NOT instance IDs
- Tag values are **case-sensitive** and must match exactly (including spaces)
- Device name is typically `nvme0n1p1` for modern instances, but verify in CloudWatch metrics if needed

## Validation

The deployment will automatically validate:
- All configured instances are found
- Instances are in the correct AWS account and region
- Tag values match exactly

If instances are not found, Terraform will fail with clear error messages indicating which instances are missing and what to check.

## Troubleshooting

### Error: "Instances not found"
- Verify instances exist in the current AWS account
- Check tag keys and values match exactly (case-sensitive, no extra spaces)
- Ensure instances are in 'running' or 'stopped' state
- Verify you're in the correct AWS region

### Error: "AuthorizationError" or "AccessDenied"
- The pre-deployment script should handle this automatically
- If it persists, manually backup and remove `terraform.tfstate` files
- Run `terraform init` again

### State File Conflicts
- The pre-deployment script automatically handles account switching
- Old state files are backed up to `terraform-state-backups/` directory
- You can restore from backup if needed

