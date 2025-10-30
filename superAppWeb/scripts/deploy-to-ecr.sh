#!/bin/bash

set -e

# Configuration
AWS_ACCOUNT_ID="012351853258"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPOSITORY="superapp"
IMAGE_TAG="${1:-latest}"

echo "=================================================="
echo "Deploying SuperApp Web to ECR"
echo "=================================================="
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"
echo "Repository: ${ECR_REPOSITORY}"
echo "Image Tag: ${IMAGE_TAG}"
echo "=================================================="

# Step 1: Create ECR repository if it doesn't exist
echo ""
echo "Step 1: Checking ECR repository..."
if ! aws ecr describe-repositories \
    --region ${AWS_REGION} \
    --repository-names ${ECR_REPOSITORY} 2>/dev/null; then
    
    echo "Creating ECR repository: ${ECR_REPOSITORY}"
    aws ecr create-repository \
        --region ${AWS_REGION} \
        --repository-name ${ECR_REPOSITORY} \
        --image-scanning-configuration scanOnPush=true \
        --tags Key=Project,Value=SuperApp Key=ManagedBy,Value=CLI
    
    echo "✓ Repository created"
else
    echo "✓ Repository already exists"
fi

# Step 2: Login to ECR
echo ""
echo "Step 2: Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "✓ Logged in to ECR"

# Step 3: Build Docker image (using Dockerfile.dev for development environment)
echo ""
echo "Step 3: Building Docker image (development)..."
docker build -f Dockerfile.dev -t ${ECR_REPOSITORY}:${IMAGE_TAG} .

echo "✓ Image built successfully"

# Step 4: Tag image for ECR
echo ""
echo "Step 4: Tagging image for ECR..."
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}

echo "✓ Image tagged"

# Step 5: Push to ECR
echo ""
echo "Step 5: Pushing image to ECR..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}

echo "✓ Image pushed successfully"

# Step 6: Display image URI
echo ""
echo "=================================================="
echo "✓ Deployment Complete!"
echo "=================================================="
echo "Image URI:"
echo "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"
echo ""
echo "Next steps:"
echo "1. Update ECS task definition with this image URI"
echo "2. Deploy/update ECS service"
echo "=================================================="
