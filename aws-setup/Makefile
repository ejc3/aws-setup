.PHONY: help shell init plan apply destroy output clean test connect connect-iam .aws-login .check-aws-cli

# Container runtime (podman or docker)
CONTAINER_RUNTIME := $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo /opt/homebrew/bin/podman)
PWD := $(shell pwd)
AWS_DIR := $(HOME)/.aws
ENV_FILE := $(PWD)/.env

ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' $(ENV_FILE))
endif

# Default target
help:
	@echo "Available targets:"
	@echo "  make init        - Initialize Terraform"
	@echo "  make plan        - Run Terraform plan"
	@echo "  make apply       - Deploy the infrastructure"
	@echo "  make connect     - Connect to MySQL database (IAM auth)"
	@echo "  make output      - Show Terraform outputs"
	@echo "  make destroy     - Destroy the infrastructure"
	@echo "  make shell       - Start an interactive shell"
	@echo "  make clean       - Clean everything"

# Ensure AWS CLI is installed via Homebrew (required for SSO)
.check-aws-cli:
	@if [ ! -f /opt/homebrew/bin/aws ]; then \
		echo "AWS CLI not found. Installing via Homebrew..."; \
		brew install awscli; \
		echo "AWS CLI installed successfully"; \
	fi

# Ensure AWS config exists
$(AWS_DIR)/config:
	@mkdir -p $(AWS_DIR)
	@echo "[default]" > $(AWS_DIR)/config
	@echo "region = us-west-1" >> $(AWS_DIR)/config
	@echo "output = json" >> $(AWS_DIR)/config

# Check if AWS credentials work, login if needed
.aws-login: .check-aws-cli $(AWS_DIR)/config .container-built
	@$(CONTAINER_RUNTIME) run -it --rm \
		-v $(AWS_DIR):/root/.aws \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		-e SSO_START_URL \
		-e SSO_REGION \
		-e SSO_ACCOUNT_ID \
		-e SSO_ROLE_NAME \
		-e AWS_REGION \
		--entrypoint /usr/local/bin/aws-login.sh \
		aws-dev
	@touch .aws-login

# Ensure terraform.tfvars exists (create if missing)
terraform.tfvars:
	@if [ ! -f terraform.tfvars ]; then \
		echo "# Terraform variables - edit as needed" > terraform.tfvars; \
		echo "# Password is auto-generated via random_password resource" >> terraform.tfvars; \
		echo "# IAM authentication enabled - use IAM tokens for connections" >> terraform.tfvars; \
		echo "Created terraform.tfvars"; \
	fi

# Build the container (internal target)
.container-built: Dockerfile aws-login.sh
	$(CONTAINER_RUNTIME) build -t aws-dev .
	@touch .container-built

# Start interactive shell
shell: .aws-login
	$(CONTAINER_RUNTIME) run -it --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		--entrypoint /bin/bash \
		aws-dev

# Terraform commands (run in container)
init: .aws-login terraform.tfvars
	$(CONTAINER_RUNTIME) run --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		aws-dev \
		init

plan: .aws-login terraform.tfvars
	$(CONTAINER_RUNTIME) run --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		aws-dev \
		plan

apply: .aws-login terraform.tfvars
	$(CONTAINER_RUNTIME) run -it --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		aws-dev \
		apply -auto-approve

destroy: .aws-login
	$(CONTAINER_RUNTIME) run -it --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		aws-dev \
		destroy -auto-approve

output: .aws-login
	$(CONTAINER_RUNTIME) run --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		aws-dev \
		output

# Connect with IAM authentication
connect: .aws-login
	@echo "Connecting to MySQL database using IAM authentication..."
	@echo "NOTE: This requires IAM policies to be configured for the user"
	@$(CONTAINER_RUNTIME) run -it --rm \
		-v $(PWD):/workspace \
		-v $(AWS_DIR):/root/.aws:ro \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_PROFILE \
		--entrypoint sh \
		aws-dev -c ' \
			ENDPOINT=$$(terraform output -raw db_address 2>/dev/null) && \
			DB_NAME=$$(terraform output -raw db_name 2>/dev/null) && \
			DB_USER="iamuser" && \
			if [ -z "$$ENDPOINT" ]; then \
				echo "ERROR: Database not deployed. Run \"make apply\" first."; \
				exit 1; \
			fi && \
			echo "Getting IAM auth token for $$ENDPOINT..." && \
			TOKEN=$$(aws rds generate-db-auth-token \
				--hostname $$ENDPOINT \
				--port 3306 \
				--username $$DB_USER \
				--region us-west-1) && \
			echo "Connecting to $$ENDPOINT as $$DB_USER using IAM token..." && \
			echo "Note: Aurora may take 15-30 seconds to resume from paused state..." && \
			mariadb --connect-timeout=60 -h $$ENDPOINT -u $$DB_USER --password="$$TOKEN" --ssl-ca=/usr/local/share/amazon-rds-ca-cert.pem --ssl $$DB_NAME \
		'

# Test container tools
test:
	@echo "Testing container tools..."
	$(CONTAINER_RUNTIME) run --rm --entrypoint /bin/bash mysql-aws-dev -c \
		"terraform --version && echo '---' && aws --version && echo '---' && mysql --version"

# Clean everything
clean:
	rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup *.tfplan .aws-login .container-built
