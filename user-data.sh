#!/bin/bash
# Bootstrap script for development instance
# Installs tools and sets up environment

set -e

# Update system
dnf update -y

# Install development tools
dnf install -y \
  git \
  make \
  docker \
  vim \
  tmux \
  jq \
  unzip

# Install Terraform (detect architecture)
TERRAFORM_VERSION="1.9.0"
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  TERRAFORM_ARCH="arm64"
else
  TERRAFORM_ARCH="amd64"
fi
wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
unzip -q terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
mv terraform /usr/local/bin/
rm terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
chmod +x /usr/local/bin/terraform

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Tailscale auth key will be provided via SSM Parameter Store
# and configured after instance launch

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Set up workspace directory
mkdir -p /home/ec2-user/workspace
chown ec2-user:ec2-user /home/ec2-user/workspace

# Configure git (ec2-user will override with their own settings)
sudo -u ec2-user git config --global init.defaultBranch main
sudo -u ec2-user git config --global pull.rebase false

# Create helpful README
cat > /home/ec2-user/README.txt <<'EOF'
Development Instance - Quick Start
==================================

This instance has the following tools installed:
- git, make, docker
- terraform (in /usr/local/bin)
- vim, tmux, jq
- aws cli (pre-installed)

Getting Started:
1. Clone your repo: git clone <repo-url> workspace/
2. cd workspace/
3. Configure git:
   git config --global user.name "Your Name"
   git config --global user.email "your@email.com"

Everything in /home/ec2-user persists when you stop/start the instance.

To use Docker: docker commands work (ec2-user is in docker group)
To exit: Just disconnect - run 'make dev-stop' from your local machine

Reconnect: make dev-ssh
EOF

chown ec2-user:ec2-user /home/ec2-user/README.txt

# The deployment script will be uploaded via Terraform file provisioner
# It will be placed at /home/ec2-user/deploy-from-github.sh

# Signal completion
echo "Bootstrap complete - instance ready for development" > /tmp/bootstrap-complete
