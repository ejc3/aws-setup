# Tailscale Integration Setup

This infrastructure includes Tailscale integration for secure access to your AWS dev instance.

## Prerequisites

1. A Tailscale account (free tier works fine)
2. OAuth client credentials from Tailscale

## Step 1: Create OAuth Client

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Click "Generate OAuth client"
3. Give it a name like "AWS Infrastructure Terraform"
4. Under "Scopes", select:
   - `devices:write` - Required to create auth keys
5. Click "Generate client"
6. Copy the Client ID and Client Secret

## Step 2: Set Environment Variables

Add these to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export TAILSCALE_OAUTH_CLIENT_ID="your-client-id-here"
export TAILSCALE_OAUTH_CLIENT_SECRET="your-client-secret-here"
```

Then reload your shell:
```bash
source ~/.zshrc  # or source ~/.bashrc
```

## Step 3: Initialize Tailscale Provider

```bash
cd /Users/ejcampbell/src/aws
terraform init
```

This will download the Tailscale provider.

## Step 4: Apply Infrastructure

```bash
terraform apply
```

This will:
1. Create a Tailscale auth key (valid for 90 days)
2. Deploy your EC2 instance with Tailscale installed

## Step 5: Configure Tailscale on EC2

After the instance is running, configure Tailscale:

```bash
# Get the auth key from Terraform
AUTH_KEY=$(terraform output -raw tailscale_auth_key)

# Get the instance ID
INSTANCE_ID=$(terraform output -raw dev_instance_id)

# Configure Tailscale on the instance
./scripts/configure-tailscale.sh "$INSTANCE_ID" "$AUTH_KEY"
```

## Step 6: Verify Connection

1. Check your Tailscale admin console: https://login.tailscale.com/admin/machines
2. You should see "aws-dev-instance" listed
3. You can now SSH directly via Tailscale:
   ```bash
   ssh ec2-user@aws-dev-instance
   ```

## Benefits

- **No public IP needed**: Your instance is only accessible via Tailscale
- **Encrypted**: All traffic is encrypted
- **Simple**: No VPN server to manage
- **Multi-platform**: Access from Mac, Linux, Windows, iOS, Android

## Troubleshooting

### Auth key expired
Auth keys expire after 90 days. To create a new one:
```bash
terraform taint tailscale_tailnet_key.dev_instance
terraform apply
```

### Instance not appearing in Tailscale
Check the instance logs:
```bash
aws ssm start-session --target $(terraform output -raw dev_instance_id)
sudo tailscale status
```

### Can't connect after setup
Make sure:
1. Tailscale is running on your local machine
2. You're logged into the same Tailnet
3. The instance shows as "Connected" in the admin console
