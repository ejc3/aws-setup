# AWS Account Tags
# Mark this account with metadata to identify its purpose

data "aws_organizations_organization" "current" {
  count = var.enable_account_tags ? 1 : 0
}

# Note: Account aliases and tags require AWS Organizations
# For a standalone account, document in outputs instead
output "account_info" {
  description = "AWS Account information and purpose"
  value = {
    account_id   = data.aws_caller_identity.current.account_id
    account_arn  = data.aws_caller_identity.current.arn
    purpose      = "Scratch/Development Account"
    environment  = "sandbox"
    managed_by   = "Terraform"
    repository   = var.github_repo
    warning      = "⚠️  SCRATCH ACCOUNT - Resources may be destroyed automatically by CI"
  }
}

