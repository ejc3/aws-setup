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

Edit `terraform.tfvars` to enable/configure components (defaults work out-of-box):

### Aurora Database (Optional)
- `enable_aurora = false` - Set to `true` to enable Aurora Serverless v2
- Password is auto-generated via Terraform random_password
- IAM authentication enabled for token-based access
- `serverless_min_capacity = 0` - Enables auto-pause
- `serverless_max_capacity = 1` - Low ceiling for dev
- `seconds_until_auto_pause = 300` - 5 minutes

### Development Instance (Optional)
- `enable_dev_instance = true` - Set to `true` to enable EC2 dev instance
- `dev_instance_type = "t2.micro"` - Instance size (~$8/month)
- `dev_volume_size = 20` - EBS volume size in GB

## Commands

### Infrastructure Management
```
make init        - Initialize (auto-builds, auto-logins, auto-creates config)
make plan        - Preview changes
make apply       - Deploy infrastructure
make output      - Show Terraform outputs
make destroy     - Remove infrastructure
make shell       - Interactive shell in container
make clean       - Clean Terraform state and artifacts
```

### Database Access (if Aurora enabled)
```
make connect     - Connect to Aurora database
```

### Development Instance (if enabled)
```
make dev-ssh     - SSH into development instance via SSM
```

Everything automatic. Container builds when Dockerfile changes. Login checks happen every time.

## Deploying Demos to AWS

The EC2 development instance can automatically deploy demos from private GitHub repositories.

### Setup GitHub Authentication

1. **Create a fine-grained GitHub Personal Access Token (PAT)**:
   - Go to: https://github.com/settings/personal-access-tokens/new
   - Token name: "AWS EC2 deployment token"
   - Expiration: Choose your preference (90 days recommended)
   - Repository access: **Only select repositories**
     - Select: `ejc3/nextjs-demos` and `ejc3/python-demos`
   - Permissions:
     - Repository permissions → Contents: **Read-only**
   - Generate and copy the token (starts with `github_pat_`)

2. **Store the token in AWS Secrets Manager**:
   ```bash
   aws secretsmanager update-secret \
       --secret-id github-deploy-token \
       --secret-string "ghp_YOUR_TOKEN_HERE" \
       --region us-west-1
   ```

### Deploying from Demo Repositories

Each demo repository (nextjs-demos, python-demos) includes a `deploy-to-aws.sh` script that:
- Finds the EC2 instance by tags (no manual instance ID needed)
- Uploads code from GitHub using the stored PAT
- Auto-detects demo type (Next.js vs Python)
- Builds and deploys all demos
- Manages processes (PM2 for Next.js, systemd for Python)

**To deploy**:
```bash
cd ~/src/nextjs-demos && ./deploy-to-aws.sh
cd ~/src/python-demos && ./deploy-to-aws.sh
```

### How It Works

1. **Tag-based discovery**: Deploy scripts query AWS EC2 for instances tagged with `AutoDeploy=true` and `Environment=dev`
2. **SSM communication**: Commands sent via AWS Systems Manager (no SSH needed)
3. **GitHub authentication**: EC2 instance fetches PAT from Secrets Manager to clone private repos
4. **Auto-detection**: Deployment script examines repo structure to determine Next.js vs Python
5. **Process management**:
   - Next.js demos run via PM2 on ports 3001-3006
   - Python demos run via systemd user services on configured ports

### Deployment Script Location

The generic deployment script lives on the EC2 instance at `/home/ec2-user/deploy-from-github.sh` and is automatically uploaded via Terraform.

## Files

- `Dockerfile` - Container with Terraform, AWS CLI, and utilities
- `Makefile` - All commands
- `main.tf` - Infrastructure definition (currently Aurora Serverless v2)
- `variables.tf` - Configuration options
- `outputs.tf` - Output values
- `terraform.tfvars` - Your configuration (not in git)

## Current Infrastructure

### Aurora Serverless v2 (Optional - disabled by default)
- Aurora Serverless v2 cluster (us-west-1)
- VPC with 2 subnets across availability zones
- Security group allowing database port 3306
- Encrypted storage
- Automated backups (7 days retention)
- Auto-pause at 0 ACU when idle

### Development EC2 Instance (Optional - disabled by default)
- Amazon Linux 2023 t2.micro instance (~$8/month)
- Accessed via AWS Systems Manager (SSM) - no SSH keys needed
- VPC endpoints for private AWS API access (no public IP required)
- Persistent EBS volume (survives stop/start)
- IAM role with:
  - SSM access for remote shell
  - Secrets Manager access for GitHub authentication
- Automatically deploys demos from private GitHub repositories

## Troubleshooting

**AWS session expired**: Just run any command - auto-detects and prompts for login

**Infrastructure not found**: Run `make apply` first to deploy

**Can't connect after apply**: Wait 5-10 minutes for resource initialization

**High costs** (Aurora): Database not pausing - check for open connections

**Container rebuild needed**: `make clean` then run your command
# Test CI
# Test CI with clean AWS account
