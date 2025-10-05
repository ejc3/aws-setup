# AWS Infrastructure Setup

Terraform + Docker setup for AWS infrastructure with automatic authentication and containerized dev environment.

**Current Configuration**: Aurora Serverless v2 sized for cost-conscious development environments.

## Cost (Current Aurora Setup)

- Dev usage (8h/day): ~$15/month
- Light usage (2h/day): ~$6/month
- Weekend project: ~$2.50/month

## Setup

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

## Configuration

Edit `terraform.tfvars` if needed (defaults work out-of-box):
- Password is auto-generated via Terraform random_password
- IAM authentication enabled for token-based access
- `serverless_min_capacity = 0.5` - Smallest Aurora Serverless v2 capacity
- `serverless_max_capacity = 1` - Low ceiling for dev

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
- Serverless capacity between 0.5 and 1 ACU

## Troubleshooting

**AWS session expired**: Just run any command - auto-detects and prompts for login

**Infrastructure not found**: Run `make apply` first to deploy

**Can't connect after apply**: Wait 5-10 minutes for resource initialization

**High costs** (Aurora): Review connections and consider reducing max capacity

**Container rebuild needed**: `make clean` then run your command
