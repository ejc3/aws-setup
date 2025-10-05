#!/bin/bash
set -e

# Import OIDC provider
terraform import aws_iam_openid_connect_provider.github_actions \
  arn:aws:iam::928413605543:oidc-provider/token.actions.githubusercontent.com

# Import IAM role
terraform import aws_iam_role.terraform_github_action TerraformGithubActionRole

# Import role policy attachment
terraform import aws_iam_role_policy_attachment.terraform_github_action_admin \
  TerraformGithubActionRole/arn:aws:iam::aws:policy/AdministratorAccess
