#!/bin/sh
set -e

# Use AWS_PROFILE if set, otherwise use default
PROFILE=${AWS_PROFILE:-default}

# Check if already logged in
if aws sts get-caller-identity >/dev/null 2>&1; then
    exit 0
fi

echo "========================================="
echo "AWS Login - Copy URL to Browser"
echo "========================================="
echo ""

# Check if this profile uses SSO
if grep -q "\[profile $PROFILE\]" ~/.aws/config 2>/dev/null && \
   grep -A10 "\[profile $PROFILE\]" ~/.aws/config | grep -q "sso_start_url"; then
    # Profile exists and uses SSO - just login
    aws sso login --profile $PROFILE --use-device-code
elif [ "$PROFILE" != "default" ]; then
    echo "Profile '$PROFILE' not found or not configured for SSO"
    echo "Available profiles:"
    grep "^\[profile" ~/.aws/config 2>/dev/null | sed 's/\[profile \(.*\)\]/  \1/' || echo "  (none)"
    exit 1
else
    # First time setup for default profile
    if [ -z "$SSO_START_URL" ]; then
        echo "FIRST TIME SETUP"
        echo ""
        echo "Get your SSO start URL:"
        echo "1. Go to: https://console.aws.amazon.com/"
        echo "2. Search for 'IAM Identity Center' in the top search bar"
        echo "3. Click on it, then go to Settings"
        echo "4. Copy the 'AWS access portal URL'"
        echo "   (looks like: https://d-xxxxxxxxxx.awsapps.com/start)"
        echo ""
        read -p "SSO start URL: " SSO_START_URL
        echo ""
    fi

    if [ -z "$SSO_ACCOUNT_ID" ]; then
        cat <<'EOF' >&2
ERROR: SSO_ACCOUNT_ID is not set.
Set the variable in your environment or define it in a .env file (see .env.example) before running make.
EOF
        exit 1
    fi

    echo "Configuring SSO..."
    echo "SSO Start URL: $SSO_START_URL"
    echo "SSO Region: ${SSO_REGION:-us-east-1}"
    echo "CLI Region: ${AWS_REGION:-us-west-1}"
    echo "Account ID: $SSO_ACCOUNT_ID"
    echo ""

    # Configure SSO with provided values including account and role
    aws configure set sso_start_url "$SSO_START_URL"
    aws configure set sso_region "${SSO_REGION:-us-east-1}"
    aws configure set sso_account_id "$SSO_ACCOUNT_ID"
    aws configure set sso_role_name "${SSO_ROLE_NAME:-AdministratorAccess}"
    aws configure set region "${AWS_REGION:-us-west-1}"

    # Login using device code flow
    echo "Starting login..."
    echo ""
    echo "Please sign in to your AWS SSO portal first:"
    echo "$SSO_START_URL"
    echo ""
    echo "Then you'll be prompted to authorize this device."
    echo ""
    aws sso login --use-device-code
fi
