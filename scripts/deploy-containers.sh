#!/bin/bash
# Deploy containerized demos from ECR to EC2 instance
# Replaces the GitHub-pull deployment model with container-based deployment

set -e

DEMO_TYPE="${1}"  # "nextjs" or "python"
AWS_REGION="${AWS_REGION:-us-west-1}"

if [ -z "$DEMO_TYPE" ]; then
    echo "Error: Demo type is required"
    echo "Usage: $0 <demo-type>"
    echo "  demo-type: nextjs or python"
    exit 1
fi

echo "==> Deploying $DEMO_TYPE demos from ECR"

# Get AWS account ID for ECR registry
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO_NAME="aws-infrastructure/demos"

echo "    Registry: $ECR_REGISTRY"
echo "    Repository: $REPO_NAME"

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "==> Installing Docker..."
    sudo dnf install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ec2-user
fi

# Authenticate with ECR
echo "==> Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    sudo docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Get list of available images for this demo type (filter by prefix)
echo "==> Fetching available images..."
ALL_IMAGES=$(aws ecr list-images \
    --repository-name "$REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'imageIds[*].imageTag' \
    --output text)

# Filter images by demo type prefix
IMAGES=$(echo "$ALL_IMAGES" | tr ' ' '\n' | grep "^${DEMO_TYPE}-" || true)

if [ -z "$IMAGES" ]; then
    echo "Error: No images found for $DEMO_TYPE in repository $REPO_NAME"
    echo "Run build-and-push.sh locally first to push images to ECR"
    exit 1
fi

echo "    Found images: $IMAGES"

# Stop existing containers for this demo type
echo "==> Stopping existing $DEMO_TYPE containers..."
sudo docker ps -a --filter "label=demo-type=$DEMO_TYPE" --format "{{.ID}}" | xargs -r sudo docker stop || true
sudo docker ps -a --filter "label=demo-type=$DEMO_TYPE" --format "{{.ID}}" | xargs -r sudo docker rm || true

# Deploy each demo
for demo_tag in $IMAGES; do
    echo ""
    echo "==> Deploying $demo_tag..."

    # Extract port from demo tag (e.g., "nextjs-01-hello-world" -> 3001 for nextjs, "python-01-talktui" -> 8001 for python)
    demo_number=$(echo "$demo_tag" | sed "s/^${DEMO_TYPE}-//" | grep -oP '^\d+')

    if [ "$DEMO_TYPE" = "nextjs" ]; then
        PORT=$((3000 + demo_number))
    else
        PORT=$((8000 + demo_number))
    fi

    # Pull image
    IMAGE_URI="${ECR_REGISTRY}/${REPO_NAME}:${demo_tag}"
    sudo docker pull "$IMAGE_URI"

    # Run container
    sudo docker run -d \
        --name "${demo_tag}" \
        --label "demo-type=${DEMO_TYPE}" \
        --label "demo-name=${demo_tag}" \
        -p "${PORT}:3000" \
        --restart=always \
        "$IMAGE_URI"

    echo "    ✓ ${demo_tag} deployed on port ${PORT}"
done

echo ""
echo "==> Deployment complete!"
echo ""
echo "Running containers:"
sudo docker ps --filter "label=demo-type=$DEMO_TYPE" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
