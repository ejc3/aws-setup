#!/bin/bash
# Bootstrap containerized Buckman infrastructure
# Runs on first boot to pull and start runner + version-server containers

set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "==> Starting Buckman infrastructure bootstrap at $(date)"

# Get GitHub token from Secrets Manager
echo "==> Fetching GitHub token from Secrets Manager"
GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "${github_token_secret_arn}" \
  --region "${aws_region}" \
  --query 'SecretString' \
  --output text)

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: Failed to fetch GitHub token from Secrets Manager"
  exit 1
fi

# Login to GitHub Container Registry
echo "==> Logging into GitHub Container Registry"
echo "$GITHUB_TOKEN" | podman login ghcr.io -u ej-campbell --password-stdin

# Pull infrastructure images
echo "==> Pulling buckman-runner image"
podman pull ghcr.io/ej-campbell/buckman-runner:latest

echo "==> Pulling buckman-version-server image"
podman pull ghcr.io/ej-campbell/buckman-version-server:latest

# Create systemd service for version-server
echo "==> Creating version-server systemd service"
cat > /etc/systemd/system/buckman-version-server.service <<'EOF'
[Unit]
Description=Buckman Version Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
ExecStartPre=-/usr/bin/podman stop buckman-version-server
ExecStartPre=-/usr/bin/podman rm buckman-version-server
ExecStart=/usr/bin/podman run \
  --rm \
  --name buckman-version-server \
  --init \
  -p 8081:8081 \
  -v /var/run:/var/run:z \
  ghcr.io/ej-campbell/buckman-version-server:latest
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
User=ec2-user
ExecStartPre=-/usr/bin/podman stop buckman-runner
ExecStartPre=-/usr/bin/podman rm buckman-runner
ExecStart=/usr/bin/podman run \
  --rm \
  --name buckman-runner \
  --init \
  -p 8080:8080 \
  -v /run/podman/podman.sock:/run/podman/podman.sock:z \
  ghcr.io/ej-campbell/buckman-runner:latest
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
