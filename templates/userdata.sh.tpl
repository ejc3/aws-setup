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

# Install AWS CLI v2 (official method for Ubuntu ARM64)
echo "==> Installing AWS CLI v2"
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Configure Podman for rootless operation
echo "==> Configuring Podman"
sudo -u ubuntu podman system migrate

# Login to ECR (uses IAM role automatically)
echo "==> Logging into Amazon ECR"
aws ecr get-login-password --region ${aws_region} | \
  sudo -u ubuntu podman login --username AWS --password-stdin ${ecr_registry}

# Login to GitHub Container Registry (for Buck app images)
echo "==> Logging into GitHub Container Registry"
GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id github-ghcr-token \
  --query SecretString \
  --output text \
  --region ${aws_region})
echo "$GITHUB_TOKEN" | sudo -u ubuntu podman login ghcr.io -u ej-campbell --password-stdin

# Pull consolidated infrastructure image from ECR
echo "==> Pulling buckman infrastructure image"
sudo -u ubuntu podman pull ${ecr_buckman_runner_image}

# Create directory for version-server state file
mkdir -p /var/run/buckman
chown ubuntu:ubuntu /var/run/buckman

# Create systemd service for version-server
echo "==> Creating version-server systemd service"
cat > /etc/systemd/system/buckman-version-server.service <<'EOF'
[Unit]
Description=Buckman Version Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
ExecStartPre=-/usr/bin/podman stop buckman-version-server
ExecStartPre=-/usr/bin/podman rm buckman-version-server
ExecStart=/usr/bin/podman run \
  --rm \
  --name buckman-version-server \
  --init \
  -p 8081:8081 \
  -v /var/run/buckman:/var/run:z \
  -v /run/podman/podman.sock:/run/podman/podman.sock:z \
  ${ecr_buckman_runner_image} \
  python version-server.py
ExecStop=/usr/bin/podman stop buckman-version-server
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for runner (with Podman socket mount)
echo "==> Creating buckman-runner systemd service"
cat > /etc/systemd/system/buckman-runner.service <<'EOF'
[Unit]
Description=Buckman Proxy Runner
After=network-online.target podman.socket buckman-version-server.service
Wants=network-online.target podman.socket
Requires=buckman-version-server.service

[Service]
Type=simple
User=ubuntu
ExecStartPre=-/usr/bin/podman stop buckman-runner
ExecStartPre=-/usr/bin/podman rm buckman-runner
ExecStart=/usr/bin/podman run \
  --rm \
  --name buckman-runner \
  --init \
  -p 8080:8080 \
  -v /run/podman/podman.sock:/run/podman/podman.sock:z \
  ${ecr_buckman_runner_image}
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
