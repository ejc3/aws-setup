#!/bin/bash
# Configure Tailscale on EC2 instance
# Usage: ./configure-tailscale.sh <instance-id> <tailscale-auth-key>

set -e

INSTANCE_ID="${1:?Instance ID required}"
AUTH_KEY="${2:?Tailscale auth key required}"
AWS_REGION="${AWS_REGION:-us-west-1}"

echo "==> Configuring Tailscale on instance $INSTANCE_ID..."

# Connect Tailscale using the auth key
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[
        'echo \"Connecting to Tailscale...\"',
        'sudo tailscale up --authkey=${AUTH_KEY} --hostname=aws-dev-instance',
        'echo \"Tailscale status:\"',
        'tailscale status'
    ]" \
    --region "$AWS_REGION" \
    --output text \
    --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting for Tailscale configuration..."

# Wait for command to complete
sleep 5

# Get the result
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'StandardOutputContent' \
    --output text

echo ""
echo "==> Tailscale configured successfully!"
echo "==> Your instance should now be accessible via Tailscale network"
echo "==> Check your Tailscale admin console: https://login.tailscale.com/admin/machines"
