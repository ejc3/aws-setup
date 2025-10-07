#!/bin/bash
# Deploy script that runs on EC2 instance
# Pulls from GitHub and deploys demos

set -e

REPO_URL="${1}"
BRANCH="${2:-main}"
AWS_REGION="${AWS_REGION:-us-west-1}"

if [ -z "$REPO_URL" ]; then
    echo "Error: Repository URL is required"
    echo "Usage: $0 <repo-url> [branch]"
    echo "  repo-url:   GitHub repository URL (required)"
    echo "  branch:     Git branch (default: main)"
    exit 1
fi

echo "==> Deploying from GitHub"
echo "    Repository: $REPO_URL"
echo "    Branch: $BRANCH"

# Get GitHub token from Secrets Manager
echo "==> Fetching GitHub token from Secrets Manager..."
GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
    --secret-id github-deploy-token \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text 2>/dev/null)

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Failed to fetch GitHub token from Secrets Manager"
    echo "Make sure you have created the secret 'github-deploy-token' with your GitHub PAT"
    exit 1
fi

# Convert SSH URL to HTTPS with token if needed
if [[ "$REPO_URL" == git@github.com:* ]]; then
    # Convert git@github.com:user/repo.git to https://TOKEN@github.com/user/repo.git
    REPO_URL_HTTPS=$(echo "$REPO_URL" | sed "s|git@github.com:|https://${GITHUB_TOKEN}@github.com/|")
else
    # Inject token into HTTPS URL
    REPO_URL_HTTPS=$(echo "$REPO_URL" | sed "s|https://github.com/|https://${GITHUB_TOKEN}@github.com/|")
fi

# Set up workspace
WORKSPACE="/home/ec2-user/workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# Clone or update repository
if [ -d ".git" ]; then
    echo "==> Updating existing repository..."
    git fetch origin
    git reset --hard "origin/$BRANCH"
    git clean -fd
else
    echo "==> Cloning repository..."
    git clone "$REPO_URL_HTTPS" .
    git checkout "$BRANCH"
fi

# Auto-detect demo type based on repository structure
DEMOS_DIR="$WORKSPACE/demos"
if [ ! -d "$DEMOS_DIR" ]; then
    echo "Error: No demos/ directory found in repository"
    exit 1
fi

# Check first demo to determine type (look for package.json or pyproject.toml)
FIRST_DEMO=$(find "$DEMOS_DIR" -mindepth 1 -maxdepth 1 -type d -name "[0-9]*" | sort | head -1)
if [ -z "$FIRST_DEMO" ]; then
    echo "Error: No numbered demo directories found"
    exit 1
fi

if [ -f "$FIRST_DEMO/package.json" ]; then
    DEMO_TYPE="nextjs"
elif [ -f "$FIRST_DEMO/pyproject.toml" ]; then
    DEMO_TYPE="python"
else
    echo "Error: Could not determine demo type (no package.json or pyproject.toml found)"
    exit 1
fi

echo "==> Detected demo type: $DEMO_TYPE"

# Deploy based on type
if [ "$DEMO_TYPE" = "nextjs" ]; then
    echo "==> Deploying Next.js demos..."

    # Install Node.js if not present
    if ! command -v node &> /dev/null; then
        echo "    Installing Node.js 18..."
        curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
        sudo dnf install -y nodejs
    fi

    # Install PM2 if not present
    if ! command -v pm2 &> /dev/null; then
        echo "    Installing PM2..."
        sudo npm install -g pm2
    fi

    # Stop existing services
    echo "    Stopping existing services..."
    pm2 delete all 2>/dev/null || true

    # Deploy each demo
    for demo_dir in $(find "$DEMOS_DIR" -mindepth 1 -maxdepth 1 -type d -name "[0-9]*" | sort); do
        demo_name=$(basename "$demo_dir")
        echo "    Deploying $demo_name..."

        cd "$demo_dir"

        # Install dependencies
        npm ci 2>&1 || npm install 2>&1

        # Build
        npm run build 2>&1

        # Extract port
        PORT=$(node -p "require('./package.json').scripts.start.match(/-p\s+(\d+)/)?.[1] || '3000'")

        # Start with PM2
        pm2 start npm --name "nextjs-$demo_name" -- start

        echo "      ✓ Deployed on port $PORT"
    done

    # Save PM2 config
    pm2 save

    # Set up PM2 startup
    pm2 startup systemd -u ec2-user --hp /home/ec2-user 2>&1 | grep -E "^sudo" | bash || true

    echo "==> Next.js deployment complete!"
    pm2 list

elif [ "$DEMO_TYPE" = "python" ]; then
    echo "==> Deploying Python demos..."

    # Install uv if not present
    if ! command -v uv &> /dev/null; then
        echo "    Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    export PATH="$HOME/.cargo/bin:$PATH"

    # Stop existing services
    echo "    Stopping existing services..."
    systemctl --user stop 'python-demo-*' 2>/dev/null || true

    # Deploy each demo
    for demo_dir in $(find "$DEMOS_DIR" -mindepth 1 -maxdepth 1 -type d -name "[0-9]*" | sort); do
        demo_name=$(basename "$demo_dir")
        echo "    Deploying $demo_name..."

        cd "$demo_dir"

        # Install dependencies
        if [ -f "pyproject.toml" ]; then
            uv sync --extra mysql 2>&1 || echo "      Warning: uv sync had issues"
        fi

        # Extract port
        PORT=$(grep -oP 'port.*?=.*?\K\d+' */config.py 2>/dev/null || echo "8000")

        # Create systemd service
        SERVICE_FILE="$HOME/.config/systemd/user/python-demo-$demo_name.service"
        mkdir -p "$HOME/.config/systemd/user"

        cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Python Demo - $demo_name
After=network.target

[Service]
Type=simple
WorkingDirectory=$demo_dir
ExecStart=$(which uv) run talk-server --host 0.0.0.0 --port $PORT
Restart=always
RestartSec=3
Environment=PATH=$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SERVICEEOF

        # Start service
        systemctl --user daemon-reload
        systemctl --user enable "python-demo-$demo_name.service"
        systemctl --user restart "python-demo-$demo_name.service"

        echo "      ✓ Deployed on port $PORT"
    done

    echo "==> Python deployment complete!"
    systemctl --user list-units --type=service 'python-demo-*' --no-pager
fi

echo ""
echo "==> Deployment finished successfully!"
