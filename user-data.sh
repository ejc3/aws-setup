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
  podman \
  python3 \
  python3-pip \
  vim \
  tmux \
  jq \
  unzip \
  curl \
  tar \
  zstd

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

# Install Buck2
echo "Installing Buck2..."
BUCK2_ARCH=$(uname -m)
if [ "$BUCK2_ARCH" = "aarch64" ]; then
  BUCK2_PLATFORM="aarch64-unknown-linux-musl"
else
  BUCK2_PLATFORM="x86_64-unknown-linux-musl"
fi

curl -sSL "https://github.com/facebook/buck2/releases/download/latest/buck2-${BUCK2_PLATFORM}.zst" -o /tmp/buck2.zst
zstd -d /tmp/buck2.zst -o /tmp/buck2
chmod +x /tmp/buck2
mv /tmp/buck2 /usr/local/bin/buck2
rm -f /tmp/buck2.zst

# Verify Buck2
buck2 --version

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Tailscale auth key will be provided via SSM Parameter Store
# and configured after instance launch

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Start and enable Podman socket
systemctl enable --now podman.socket

# Configure Podman for ec2-user (rootless)
sudo -u ec2-user podman system migrate || true

# Set up buckman directory
mkdir -p /home/ec2-user/buckman
chown -R ec2-user:ec2-user /home/ec2-user/buckman

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
- git, make, docker, podman
- buck2 (in /usr/local/bin)
- terraform (in /usr/local/bin)
- python3, pip3
- vim, tmux, jq
- aws cli (pre-installed)

Getting Started:
1. Clone your repo: git clone <repo-url> workspace/
2. cd workspace/
3. Configure git:
   git config --global user.name "Your Name"
   git config --global user.email "your@email.com"

Everything in /home/ec2-user persists when you stop/start the instance.

Buckman deployment directory: /home/ec2-user/buckman

To use Docker: docker commands work (ec2-user is in docker group)
To use Podman: podman commands work (rootless)
To use Buck2: buck2 --version

To exit: Just disconnect - run 'make dev-stop' from your local machine

Reconnect: make dev-ssh
EOF

chown ec2-user:ec2-user /home/ec2-user/README.txt

# The deployment script will be uploaded via Terraform file provisioner
# It will be placed at /home/ec2-user/deploy-from-github.sh

# Signal completion
echo "Bootstrap complete - instance ready for development" > /tmp/bootstrap-complete
