terraform {
  backend "s3" {
    # Backend configuration is provided via -backend-config flag
    # Each workspace uses its own backend config file:
    #   terraform init -backend-config=backend-business-apt.hcl
    #   terraform init -backend-config=backend-account-b.hcl
    # etc.
  }
}

