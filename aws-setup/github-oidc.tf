# GitHub Actions OIDC Provider for AWS
# Run this once to enable GitHub Actions to deploy to your AWS account

variable "github_repo" {
  description = "GitHub repository in format: username/repo"
  type        = string
  default     = ""  # Set via TF_VAR_github_repo in .env or pass via -var
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd", # Backup thumbprint
  ]

  tags = {
    Name        = "github-actions"
    Description = "OIDC provider for GitHub Actions"
  }
}

resource "aws_iam_role" "terraform_github_action" {
  name               = "TerraformGithubActionRole"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name        = "TerraformGithubActionRole"
    Description = "Role assumed by GitHub Actions for Terraform operations"
  }
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

# Grant full access for sandbox testing
# In production, narrow this down to specific permissions
resource "aws_iam_role_policy_attachment" "terraform_github_action_admin" {
  role       = aws_iam_role.terraform_github_action.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_oidc_setup" {
  value = <<-EOT
    GitHub OIDC Setup Complete!

    IAM Role ARN: ${aws_iam_role.terraform_github_action.arn}
    Account ID: ${data.aws_caller_identity.current.account_id}

    This role can now be assumed by GitHub Actions in: ${var.github_repo}
  EOT
}
