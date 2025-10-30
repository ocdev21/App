#!/bin/bash

set -e

echo "=================================================="
echo "TSApp - Deploy to ECR"
echo "=================================================="
echo ""

# Configuration
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="012351853258"
ECR_REPO_NAME="tsapp"
IMAGE_TAG="${1:-latest}"

# Navigate to tsapp directory
cd "$(dirname "$0")/.."

echo "Step 1: Creating ECR repository (if not exists)..."
aws ecr describe-repositories \
  --repository-names $ECR_REPO_NAME \
  --region $AWS_REGION 2>/dev/null || \
aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true

echo "✓ ECR repository ready: $ECR_REPO_NAME"

echo ""
echo "Step 2: Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "✓ Logged into ECR"

echo ""
echo "Step 3: Building Docker image..."
docker build -t $ECR_REPO_NAME:$IMAGE_TAG .

echo "✓ Docker image built: $ECR_REPO_NAME:$IMAGE_TAG"

echo ""
echo "Step 4: Tagging image for ECR..."
docker tag $ECR_REPO_NAME:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG

echo "✓ Image tagged"

echo ""
echo "Step 5: Pushing to ECR..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG

echo "✓ Image pushed to ECR"

echo ""
echo "=================================================="
echo "✓ SUCCESS! TSApp deployed to ECR"
echo "=================================================="
echo ""
echo "Image URI:"
echo "  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG"
echo ""
echo "Next steps:"
echo "  1. Register ECS task definition:"
echo "     cd tsapp && aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json"
echo ""
echo "  2. Create ECS service:"
echo "     ./scripts/create-ecs-service.sh"
