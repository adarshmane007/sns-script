# Pre-deployment check script for one-click deployment (Windows PowerShell)
# Automatically handles state file cleanup when switching AWS accounts

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pre-Deployment Check" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get current AWS account ID
try {
    $currentAccount = (aws sts get-caller-identity --query Account --output text 2>$null)
    if ([string]::IsNullOrEmpty($currentAccount)) {
        Write-Host "ERROR: AWS credentials not configured or invalid" -ForegroundColor Red
        Write-Host "Please configure AWS credentials and try again" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Failed to get AWS account ID. Please check AWS credentials." -ForegroundColor Red
    exit 1
}

$currentRegion = $env:AWS_REGION
if ([string]::IsNullOrEmpty($currentRegion)) {
    $currentRegion = (aws configure get region 2>$null)
    if ([string]::IsNullOrEmpty($currentRegion)) {
        $currentRegion = "ap-south-1"
    }
}

Write-Host "Current AWS Account: $currentAccount" -ForegroundColor Green
Write-Host "Current Region: $currentRegion" -ForegroundColor Green
Write-Host ""

# Check if state file exists
if (Test-Path "terraform.tfstate") {
    Write-Host "State file found. Checking for account mismatch..." -ForegroundColor Yellow
    
    $stateContent = Get-Content "terraform.tfstate" -Raw
    $stateAccount = $null
    
    # Try to extract account ID from state file
    if ($stateContent -match 'arn:aws:[^:]+:[^:]+:(\d{12})') {
        $stateAccount = $matches[1]
    }
    
    if ($null -ne $stateAccount -and $stateAccount -ne $currentAccount) {
        Write-Host "WARNING: Account mismatch detected!" -ForegroundColor Yellow
        Write-Host "   State file account: $stateAccount" -ForegroundColor Yellow
        Write-Host "   Current account:    $currentAccount" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Backing up old state file and cleaning for new account..." -ForegroundColor Yellow
        
        # Create backup directory with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupDir = "terraform-state-backups\${timestamp}_account_${stateAccount}"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        
        # Backup all state files
        Copy-Item "terraform.tfstate" "$backupDir\" -ErrorAction SilentlyContinue
        Copy-Item "terraform.tfstate.backup" "$backupDir\" -ErrorAction SilentlyContinue
        Get-ChildItem "terraform.tfstate.*.backup" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName "$backupDir\" -ErrorAction SilentlyContinue
        }
        
        Write-Host "State files backed up to: $backupDir" -ForegroundColor Green
        Write-Host ""
        Write-Host "Removing old state files..." -ForegroundColor Yellow
        
        # Remove old state files
        Remove-Item "terraform.tfstate" -ErrorAction SilentlyContinue
        Remove-Item "terraform.tfstate.backup" -ErrorAction SilentlyContinue
        Remove-Item "terraform.tfstate.*.backup" -ErrorAction SilentlyContinue
        
        Write-Host "State files cleaned. Ready for fresh deployment." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "State file account matches current account. Proceeding..." -ForegroundColor Green
        Write-Host ""
    }
} else {
    Write-Host "No state file found. This appears to be a fresh deployment." -ForegroundColor Green
    Write-Host ""
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pre-deployment check complete!" -ForegroundColor Green
Write-Host "You can now run: terraform init && terraform apply" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan

