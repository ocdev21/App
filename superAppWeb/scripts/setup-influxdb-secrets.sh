#!/bin/bash

set -e

echo "=================================================="
echo "AWS Secrets Manager - Store InfluxDB Credentials"
echo "=================================================="
echo ""

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="superapp-influxdb-credentials"
INFLUXDB_ENDPOINT="https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws"

echo "This script will store your InfluxDB credentials in AWS Secrets Manager."
echo ""
echo "Configuration:"
echo "  Secret Name: $SECRET_NAME"
echo "  AWS Region: $AWS_REGION"
echo "  InfluxDB Endpoint: $INFLUXDB_ENDPOINT"
echo ""

# Prompt for credentials
echo "Please provide your InfluxDB credentials:"
echo ""

# Get token
read -s -p "InfluxDB Token: " INFLUXDB_TOKEN
echo ""

# Get organization
read -p "InfluxDB Organization: " INFLUXDB_ORG
echo ""

# Get bucket (with default)
read -p "InfluxDB Bucket [superAppDB]: " INFLUXDB_BUCKET
INFLUXDB_BUCKET=${INFLUXDB_BUCKET:-superAppDB}
echo ""

# Validate inputs
if [ -z "$INFLUXDB_TOKEN" ]; then
  echo "❌ ERROR: Token cannot be empty"
  exit 1
fi

if [ -z "$INFLUXDB_ORG" ]; then
  echo "❌ ERROR: Organization cannot be empty"
  exit 1
fi

echo "Summary:"
echo "  Endpoint: $INFLUXDB_ENDPOINT"
echo "  Organization: $INFLUXDB_ORG"
echo "  Bucket: $INFLUXDB_BUCKET"
echo "  Token: ****${INFLUXDB_TOKEN: -4}"
echo ""

# Confirm
read -p "Create/update this secret? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Step 1: Checking if secret exists..."

# Check if secret exists
SECRET_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" 2>/dev/null || echo "NOT_FOUND")

if [ "$SECRET_EXISTS" = "NOT_FOUND" ]; then
  # Create new secret
  echo ""
  echo "Step 2: Creating new secret..."
  
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "InfluxDB credentials for superapp applications (esapp, tsapp)" \
    --secret-string "{
      \"INFLUXDB_URL\": \"$INFLUXDB_ENDPOINT\",
      \"INFLUXDB_TOKEN\": \"$INFLUXDB_TOKEN\",
      \"INFLUXDB_ORG\": \"$INFLUXDB_ORG\",
      \"INFLUXDB_BUCKET\": \"$INFLUXDB_BUCKET\"
    }" \
    --region "$AWS_REGION" > /dev/null
  
  echo "✓ Secret created successfully"
else
  # Update existing secret
  echo "⚠️  Secret already exists"
  echo ""
  echo "Step 2: Updating secret..."
  
  aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "{
      \"INFLUXDB_URL\": \"$INFLUXDB_ENDPOINT\",
      \"INFLUXDB_TOKEN\": \"$INFLUXDB_TOKEN\",
      \"INFLUXDB_ORG\": \"$INFLUXDB_ORG\",
      \"INFLUXDB_BUCKET\": \"$INFLUXDB_BUCKET\"
    }" \
    --region "$AWS_REGION" > /dev/null
  
  echo "✓ Secret updated successfully"
fi

# Get the secret ARN
echo ""
echo "Step 3: Retrieving secret ARN..."

SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query 'ARN' \
  --output text)

echo "✓ Secret ARN: $SECRET_ARN"

echo ""
echo "=================================================="
echo "✓ SUCCESS! InfluxDB credentials stored"
echo "=================================================="
echo ""
echo "Secret Details:"
echo "  Name: $SECRET_NAME"
echo "  ARN: $SECRET_ARN"
echo "  Region: $AWS_REGION"
echo ""
echo "Next Steps:"
echo ""
echo "1. Grant IAM permissions to ECS execution role:"
echo "   ./scripts/grant-influxdb-secrets-access.sh"
echo ""
echo "2. Deploy esapp with InfluxDB integration:"
echo "   cd esapp"
echo "   ./scripts/deployes-to-ecr.sh"
echo "   ./scripts/create-ecs-service.sh"
echo ""
echo "3. Deploy tsapp with InfluxDB integration:"
echo "   cd tsapp"
echo "   ./scripts/deployts-to-ecr.sh"
echo "   ./scripts/create-ecs-service.sh"
echo ""
echo "Your ECS task definitions are already configured to use these credentials!"
