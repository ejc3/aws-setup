#!/bin/bash
# Bootstrap containerized Buckman infrastructure
# Runs on first boot to pull and start runner + version-server containers

set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "==> Starting Buckman infrastructure bootstrap at $(date)"

# Install Podman and dependencies
echo "==> Installing Podman and dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y podman unzip curl

# Install AWS CLI v2 (official method for Ubuntu AMD64/x86_64)
echo "==> Installing AWS CLI v2"
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Configure Podman for root operation
echo "==> Configuring Podman"
# No migration needed - using root Podman

# Login to ECR as root (uses IAM role automatically)
echo "==> Logging into Amazon ECR"
aws ecr get-login-password --region ${aws_region} | \
  podman login --username AWS --password-stdin ${ecr_registry}

# Login to GitHub Container Registry as root (for Buck app images)
echo "==> Logging into GitHub Container Registry"
GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id github-ghcr-token \
  --query SecretString \
  --output text \
  --region ${aws_region})
echo "$GITHUB_TOKEN" | podman login ghcr.io -u ej-campbell --password-stdin

# Verify auth file was created
echo "==> Verifying GHCR auth file"
ls -la /run/containers/0/auth.json

# Read image tags from Parameter Store (set by CI on deployment)
echo "==> Reading image tags from Parameter Store"
RUNNER_TAG=$(aws ssm get-parameter --name /buckman/runner-image-tag --query Parameter.Value --output text --region ${aws_region} 2>/dev/null || echo "initial")
VERSION_SERVER_TAG=$(aws ssm get-parameter --name /buckman/version-server-image-tag --query Parameter.Value --output text --region ${aws_region} 2>/dev/null || echo "initial")

echo "Runner image tag from Parameter Store: $RUNNER_TAG"
echo "Version-server image tag from Parameter Store: $VERSION_SERVER_TAG"

# Fallback to :latest if Parameter Store has "initial" placeholder
# This allows Terraform to work on first apply before CI runs
if [ "$RUNNER_TAG" = "initial" ]; then
  echo "⚠️  WARNING: Parameter Store has 'initial' value for runner tag"
  echo "   Falling back to :latest tag (requires CI to have run at least once)"
  RUNNER_TAG="latest"
fi

if [ "$VERSION_SERVER_TAG" = "initial" ]; then
  echo "⚠️  WARNING: Parameter Store has 'initial' value for version-server tag"
  echo "   Falling back to :latest tag (requires CI to have run at least once)"
  VERSION_SERVER_TAG="latest"
fi

echo "Final runner image tag: $RUNNER_TAG"
echo "Final version-server image tag: $VERSION_SERVER_TAG"

# Construct full ECR image URLs
RUNNER_IMAGE="${account_id}.dkr.ecr.${aws_region}.amazonaws.com/aws-infrastructure/buckman-runner:$RUNNER_TAG"
VERSION_SERVER_IMAGE="${account_id}.dkr.ecr.${aws_region}.amazonaws.com/aws-infrastructure/buckman-version-server:$VERSION_SERVER_TAG"

# Pull infrastructure images from ECR
echo "==> Pulling buckman-runner image"
podman pull $RUNNER_IMAGE

echo "==> Pulling buckman-version-server image"
podman pull $VERSION_SERVER_IMAGE

# Create directory for version-server state file (owned by root)
mkdir -p /var/run/buckman

# Create systemd service for version-server (runs as root)
echo "==> Creating version-server systemd service"
cat > /etc/systemd/system/buckman-version-server.service <<EOF
[Unit]
Description=Buckman Version Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=-/usr/bin/podman stop buckman-version-server
ExecStartPre=-/usr/bin/podman rm buckman-version-server
ExecStart=/usr/bin/podman run \\
  --rm \\
  --name buckman-version-server \\
  -p 8081:8081 \\
  -v /var/run/buckman:/var/run:z \\
  -v /run/podman/podman.sock:/run/podman/podman.sock:z \\
  $VERSION_SERVER_IMAGE
ExecStop=/usr/bin/podman stop buckman-version-server
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for runner (runs as root with auth file mount)
echo "==> Creating buckman-runner systemd service"
cat > /etc/systemd/system/buckman-runner.service <<EOF
[Unit]
Description=Buckman Proxy Runner
After=network-online.target buckman-version-server.service
Wants=network-online.target
Requires=buckman-version-server.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/podman stop buckman-runner
ExecStartPre=-/usr/bin/podman rm buckman-runner
ExecStart=/usr/bin/podman run \\
  --rm \\
  --name buckman-runner \\
  -p 8080:8080 \\
  -e REGISTRY_AUTH_FILE=/run/containers-auth/auth.json \\
  -v /run/podman/podman.sock:/run/podman/podman.sock:z \\
  -v /run/containers/0/auth.json:/run/containers-auth/auth.json:ro,z \\
  $RUNNER_IMAGE
ExecStop=/usr/bin/podman stop buckman-runner
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo "==> Enabling and starting services"
systemctl daemon-reload
systemctl enable buckman-version-server
systemctl enable buckman-runner
systemctl start buckman-version-server
systemctl start buckman-runner

echo "==> Bootstrap complete at $(date)"
echo "==> Services status:"
systemctl status buckman-version-server --no-pager || true
systemctl status buckman-runner --no-pager || true
