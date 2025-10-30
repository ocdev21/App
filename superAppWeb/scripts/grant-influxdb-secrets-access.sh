#!/bin/bash

set -e

echo "=================================================="
echo "Grant ECS Execution Role Access to InfluxDB Secrets"
echo "=================================================="
echo ""

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="012351853258"
EXECUTION_ROLE_NAME="superapp-ecs-execution"
SECRET_NAME="superapp-influxdb-credentials"

echo "Configuration:"
echo "  Execution Role: $EXECUTION_ROLE_NAME"
echo "  Secret Name: $SECRET_NAME"
echo "  AWS Region: $AWS_REGION"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo ""

# Get secret ARN
echo "Step 1: Retrieving secret ARN..."

SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query 'ARN' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$SECRET_ARN" = "NOT_FOUND" ]; then
  echo "❌ ERROR: Secret '$SECRET_NAME' not found"
  echo ""
  echo "Create it first with:"
  echo "  ./scripts/setup-influxdb-secrets.sh"
  exit 1
fi

echo "✓ Secret ARN: $SECRET_ARN"

# Create IAM policy document
echo ""
echo "Step 2: Creating IAM policy for Secrets Manager access..."

POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "$SECRET_ARN"
      ]
    }
  ]
}
EOF
)

POLICY_NAME="superapp-influxdb-secrets-access"

# Check if policy exists
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
POLICY_EXISTS=$(aws iam get-policy \
  --policy-arn "$POLICY_ARN" 2>/dev/null || echo "NOT_FOUND")

if [ "$POLICY_EXISTS" = "NOT_FOUND" ]; then
  # Create new policy
  echo "Creating new policy: $POLICY_NAME"
  
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --description "Allow ECS tasks to read InfluxDB credentials from Secrets Manager" \
    --policy-document "$POLICY_DOCUMENT" > /dev/null
  
  echo "✓ Policy created: $POLICY_ARN"
else
  # Update existing policy (create new version)
  echo "Policy already exists, creating new version..."
  
  # Delete oldest version if at limit (5 versions max)
  VERSION_COUNT=$(aws iam list-policy-versions \
    --policy-arn "$POLICY_ARN" \
    --query 'Versions | length(@)' \
    --output text)
  
  if [ "$VERSION_COUNT" -ge 5 ]; then
    OLDEST_VERSION=$(aws iam list-policy-versions \
      --policy-arn "$POLICY_ARN" \
      --query 'Versions[?!IsDefaultVersion] | sort_by(@, &CreateDate) | [0].VersionId' \
      --output text)
    
    echo "Deleting oldest policy version: $OLDEST_VERSION"
    aws iam delete-policy-version \
      --policy-arn "$POLICY_ARN" \
      --version-id "$OLDEST_VERSION"
  fi
  
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document "$POLICY_DOCUMENT" \
    --set-as-default > /dev/null
  
  echo "✓ Policy updated: $POLICY_ARN"
fi

# Attach policy to execution role
echo ""
echo "Step 3: Attaching policy to execution role..."

aws iam attach-role-policy \
  --role-name "$EXECUTION_ROLE_NAME" \
  --policy-arn "$POLICY_ARN" 2>/dev/null || true

echo "✓ Policy attached to role: $EXECUTION_ROLE_NAME"

# Verify attachment
echo ""
echo "Step 4: Verifying policy attachment..."

ATTACHED=$(aws iam list-attached-role-policies \
  --role-name "$EXECUTION_ROLE_NAME" \
  --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyName" \
  --output text)

if [ -n "$ATTACHED" ]; then
  echo "✓ Verified: Policy is attached to role"
else
  echo "⚠️  Warning: Could not verify policy attachment"
fi

echo ""
echo "=================================================="
echo "✓ SUCCESS! IAM permissions configured"
echo "=================================================="
echo ""
echo "The ECS execution role can now access InfluxDB credentials."
echo ""
echo "Next Steps:"
echo ""
echo "1. Deploy esapp with InfluxDB integration:"
echo "   cd esapp"
echo "   ./scripts/deployes-to-ecr.sh"
echo "   ./scripts/create-ecs-service.sh"
echo ""
echo "2. Deploy tsapp with InfluxDB integration:"
echo "   cd tsapp"
echo "   ./scripts/deployts-to-ecr.sh"
echo "   ./scripts/create-ecs-service.sh"
echo ""
echo "3. Monitor logs:"
echo "   aws logs tail /aws/ecs/esapp --follow"
echo "   aws logs tail /aws/ecs/tsapp --follow"
