# Testing, Multi-Account Strategy, and CI/CD

This guide expands on the quick-start instructions in the main README. It covers
how to choose an AWS account for sandbox testing, ways to connect multiple
accounts under a shared bill, and how to run Terraform in GitHub Actions using
OpenID Connect (OIDC).

## 1. Choose the right AWS account for testing

For any infrastructure that may be destroyed frequently, spin it up in an
isolated **sandbox account**. The easiest path is to create an AWS Organization
from your primary ("payer") account:

1. In the AWS console, open **AWS Organizations** and choose **Create
   organization** (if you do not already have one). Pick the **All features**
   option so you can share billing and use service control policies later.
2. From the Organizations console select **Add an AWS account → Create an AWS
   account**. Give it a name such as `terraform-sandbox` and supply an email
   alias you control.
3. The new member account inherits the payer account's billing relationship and
   can be closed later without impacting production resources.
4. Inside the sandbox account, enable AWS IAM Identity Center (SSO) and create
   the same permission sets you use in production (for example
   `AdministratorAccess`). Your Identity Center users can then log into both the
   sandbox and production accounts with the same identities.

You can also invite an existing standalone account into the organization with
**Add an AWS account → Invite an existing AWS account** to consolidate billing
without recreating resources.

## 2. Share billing across accounts

As soon as the sandbox account is in your organization, AWS automatically
consolidates usage and invoices in the management (payer) account. To keep costs
visible:

- Enable **Cost Explorer** and **Budgets** in the payer account.
- Create a **Cost Category** or tagging strategy (for example, tag all test
  resources with `environment=sandbox`).
- Optionally set service control policies that restrict expensive operations in
  the sandbox environment.

## 3. Provide alternate deployment targets

There are two simple approaches when you need "alt" deployments for staging vs
production:

### a. Separate accounts (recommended)

Use Terraform workspaces to keep state distinct in each account:

```bash
make shell
terraform workspace new sandbox   # one-time
terraform workspace select sandbox
terraform apply                    # deploy to sandbox account
```

When you switch to production, set `AWS_PROFILE` or `SSO_ACCOUNT_ID` to point to
that account, select the `default` workspace, and apply again. Each workspace
has its own state file, preventing accidental cross-environment changes.

### b. Single account with per-environment variable files

If account separation is not possible, create per-environment `.tfvars` files:

```bash
cp terraform.tfvars env.sandbox.tfvars
# tweak identifiers, instance sizes, CIDR blocks, etc.

make plan TF_CLI_ARGS_plan="-var-file=env.sandbox.tfvars"
make apply TF_CLI_ARGS_apply="-var-file=env.sandbox.tfvars"
```

The `TF_CLI_ARGS_*` environment variables propagate through the containerized
`make` targets, letting you reuse the same commands for each environment.

## 4. Configure GitHub Actions CI for Terraform

The repository now includes `.github/workflows/terraform-ci.yml`, which runs
`terraform fmt`, `init`, `validate`, and `plan` on every push and pull request
to `main`. The workflow is pre-configured to assume
`arn:aws:iam::928413605543:role/TerraformGithubActionRole`. To finish wiring it
up:

1. **Create `TerraformGithubActionRole` in account `928413605543`.**
   - Trust policy: allow the GitHub OIDC provider
     (`token.actions.githubusercontent.com`) and restrict the audience to your
     repository (`repo:<owner>/<repo>:ref:refs/heads/main` for pushes and
     `repo:<owner>/<repo>:pull_request` for PRs).
   - Permissions policy: start with `AdministratorAccess` (sandbox only) or a
     least-privilege policy that lets Terraform manage the resources in this
     repo.
2. **Override the defaults if needed.** Create repository variables named
   `AWS_ACCOUNT_ID` and/or `AWS_TERRAFORM_ROLE_NAME` when you want to point CI at
   a different account or role name. You can also set `AWS_REGION` to change the
   execution region (default `us-west-1`).
3. Push a commit—GitHub Actions will assume the role and produce a plan artifact
   (`tfplan.binary`) you can download from the workflow run.

For full automation (applying changes), add a second job that requires manual
approval or uses a protected environment, then run
`terraform apply -auto-approve < plan-file` against the stored plan artifact.

## 5. Keep secrets out of version control

- Avoid committing real AWS account IDs or Terraform state files. The sandbox
  account `928413605543` appears in the workflow intentionally for testing, but
  production IDs should stay private.
- Use `.env` locally for SSO values. In CI, rely on the IAM role and repository
  secrets instead of storing long-lived credentials. The workflow masks the
  account ID and role name before any Terraform commands run so they do not show
  up in GitHub Actions logs.

With this setup you can experiment safely in a throwaway account, share billing
with your primary organization, and have automated feedback on every change via
GitHub Actions.
