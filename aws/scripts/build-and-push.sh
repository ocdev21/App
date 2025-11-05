#!/bin/bash
# Build and push Docker image to AWS ECR
# Usage: ./build-and-push.sh <AWS_ACCOUNT_ID> <AWS_REGION> <IMAGE_TAG>

set -e

# Configuration
AWS_ACCOUNT_ID=${1:-"123456789012"}
AWS_REGION=${2:-"us-east-1"}
IMAGE_TAG=${3:-"latest"}
ECR_REPO_NAME="l1-integrated"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "=========================================="
echo "Building and Pushing L1 Image to AWS ECR"
echo "=========================================="
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "AWS Region: ${AWS_REGION}"
echo "ECR Repository: ${ECR_REPO_NAME}"
echo "Image Tag: ${IMAGE_TAG}"
echo "=========================================="

# Authenticate Docker to ECR
echo "Authenticating to AWS ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_URI}

# Create ECR repository if it doesn't exist
echo "Ensuring ECR repository exists..."
aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} 2>/dev/null || \
    aws ecr create-repository \
        --repository-name ${ECR_REPO_NAME} \
        --region ${AWS_REGION} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256

# Build Docker image
echo "Building Docker image..."
cd ..  # Go to project root
docker build -f aws/Dockerfile -t ${ECR_REPO_NAME}:${IMAGE_TAG} .

# Tag image for ECR
echo "Tagging image..."
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URI}:latest

# Push to ECR
echo "Pushing image to ECR..."
docker push ${ECR_URI}:${IMAGE_TAG}
docker push ${ECR_URI}:latest

echo "=========================================="
echo "✅ Image successfully pushed to ECR!"
echo "Image URI: ${ECR_URI}:${IMAGE_TAG}"
echo "=========================================="
