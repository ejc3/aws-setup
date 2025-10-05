#!/bin/bash
# Bootstrap script to create S3 bucket and DynamoDB table for Terraform remote state

set -e

REGION="us-west-1"
BUCKET="ejc3-aws-infra-tfstate-928413605543"
DYNAMODB_TABLE="terraform-state-lock"

echo "Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  2>/dev/null || echo "Bucket already exists"

echo "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --region "$REGION"

echo "Enabling encryption on S3 bucket..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' \
  --region "$REGION"

echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  2>/dev/null || echo "DynamoDB table already exists"

echo "✅ Backend resources created successfully!"
echo ""
echo "Next steps:"
echo "  1. Run: terraform init -migrate-state"
echo "  2. Terraform will ask to migrate local state to S3"
echo "  3. Answer 'yes' to migrate"
