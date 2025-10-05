# AWS Infrastructure Setup

Terraform + Docker setup for AWS infrastructure with automatic authentication and containerized dev environment.

**Current Configuration**: Aurora Serverless v2 with 0 ACU auto-pause - pauses after 5 minutes idle = $0 compute charges when not in use.

## Cost (Current Aurora Setup)

- Dev usage (8h/day): ~$15/month
- Light usage (2h/day): ~$6/month
- Weekend project: ~$2.50/month

## Setup

1. Configure your AWS account ID for SSO (required – there is no default):

   ```bash
   cp .env.example .env              # create a private env file (ignored by git)
   echo "SSO_ACCOUNT_ID=928413605543" >> .env   # matches the default CI sandbox
   # or export SSO_ACCOUNT_ID in your shell before running make
   ```

   The `make` targets load values from `.env` automatically and the login helper
   aborts if `SSO_ACCOUNT_ID` is missing, preventing accidental reuse of a shared
   default.

2. Deploy and manage the stack:

   ```bash
   # 1. Deploy
   make init    # Auto-builds container, auto-creates config, auto-logs in
                # Paste URL in browser when prompted
                # Password is auto-generated (IAM authentication enabled)
   make plan
   make apply

   # 2. Connect (if deploying database)
   make connect # Auto-connects to database

   # 3. Destroy
   make destroy
   ```

**Wake up and deploy:**
```bash
make apply # Handles everything: build, login, deploy
```

## Test safely before production

- **Spin up a sandbox account.** Use AWS Organizations to create or invite a
  dedicated development account that rolls up to your primary payer account so
  you can share billing while keeping experiments isolated.
- **Reuse the same SSO identities.** Enable IAM Identity Center in that sandbox
  account and create the same permission sets you use in production so you can
  switch accounts with the SSO start URL alone.
- **Track costs.** Turn on Cost Explorer/Budgets in the payer account and tag
  sandbox resources (for example, `environment=sandbox`).

See [`docs/multi-account-and-ci.md`](docs/multi-account-and-ci.md) for
step-by-step guidance on creating and linking the account.

## Continuous integration with GitHub Actions

This repo ships with `.github/workflows/terraform-ci.yml`, which runs Terraform
formatting, validation, and a `plan` on pushes and pull requests to `main`.

The workflow targets the sandbox/test account `928413605543` by default and
assumes a role named `TerraformGithubActionRole`. To enable it:

1. In account `928413605543`, create an IAM role called
   `TerraformGithubActionRole` that trusts GitHub's OIDC provider
   (`token.actions.githubusercontent.com`) and allows the Terraform actions you
   expect (start with `AdministratorAccess` if you're unsure and restrict later).
   Scope the trust policy to this repository using the `aud` and `sub`
   conditions recommended by AWS.
2. (Optional) If you need to target a different sandbox account or role name,
   create repository variables named `AWS_ACCOUNT_ID` and/or
   `AWS_TERRAFORM_ROLE_NAME` with your overrides. The workflow will use those
   values instead of the defaults on the next run.
3. (Optional) Define a repository variable `AWS_REGION` if you want CI to run in
   a different region than the default (`us-west-1`).

The workflow masks the configured account ID and role name so they do not show
up in GitHub Actions logs, even though the sandbox defaults live in the
workflow file itself.

Each workflow run uploads the generated plan (`tfplan.binary`) as an artifact so
you can download and apply it manually or feed it into an approval step—no
long-lived credentials or secrets are required.

## Alternate deployment targets

Need an "alt" deployment (for example, staging vs. production)? Pick one of two
approaches:

- **Separate Terraform workspaces per account.** `make shell`, then run
  `terraform workspace new sandbox` (once) and `terraform workspace select` to
  switch between environments. Keep `SSO_ACCOUNT_ID` pointing at the matching
  AWS account before you `make apply`.
- **Per-environment variable files in one account.** Copy `terraform.tfvars` to
  `env.sandbox.tfvars`, tweak the values, and pass
  `TF_CLI_ARGS_plan="-var-file=env.sandbox.tfvars"` (and the matching
  `TF_CLI_ARGS_apply`) when you invoke `make`.

Both strategies keep state files separate and prevent accidental cross-
environment changes. Additional details live in
[`docs/multi-account-and-ci.md`](docs/multi-account-and-ci.md).

## Auto-Pause (Aurora Feature)

- Database pauses after 5 minutes of inactivity
- Resumes in ~15 seconds on first connection
- $0 compute charges while paused
- Only pay for storage (~$1/month for 10GB)

## Configuration

Edit `terraform.tfvars` if needed (defaults work out-of-box):
- Password is auto-generated via Terraform random_password
- IAM authentication enabled for token-based access
- `serverless_min_capacity = 0` - Enables auto-pause
- `serverless_max_capacity = 1` - Low ceiling for dev
- `seconds_until_auto_pause = 300` - 5 minutes

## Commands

```
make init     - Initialize (auto-builds, auto-logins, auto-creates config)
make plan     - Preview changes
make apply    - Deploy infrastructure
make connect  - Connect to database (if deployed)
make output   - Show Terraform outputs
make destroy  - Remove infrastructure
make shell    - Interactive shell in container
make clean    - Clean Terraform state and artifacts
```

Everything automatic. Container builds when Dockerfile changes. Login checks happen every time.

## Files

- `Dockerfile` - Container with Terraform, AWS CLI, and utilities
- `Makefile` - All commands
- `main.tf` - Infrastructure definition (currently Aurora Serverless v2)
- `variables.tf` - Configuration options
- `outputs.tf` - Output values
- `terraform.tfvars` - Your configuration (not in git)

## Current Infrastructure (Aurora Serverless v2)

- Aurora Serverless v2 cluster (us-west-1)
- VPC with 2 subnets across availability zones
- Security group allowing database port 3306
- Encrypted storage
- Automated backups (7 days retention)
- Auto-pause at 0 ACU when idle

## Troubleshooting

**AWS session expired**: Just run any command - auto-detects and prompts for login

**Infrastructure not found**: Run `make apply` first to deploy

**Can't connect after apply**: Wait 5-10 minutes for resource initialization

**High costs** (Aurora): Database not pausing - check for open connections

**Container rebuild needed**: `make clean` then run your command

---

## Background

Suprisingly difficult to setup a *basic* AWS account from scratch, but this project finally does it with Terraform and a make file to wrap standard commands. (Personal project so don't think this is production grade or anything).

