#!/bin/bash

# Build script for Benchmark Genius Docker image
# This script builds the Docker image and pushes it to the local registry

set -e

IMAGE_NAME="benchmark-genius"
REGISTRY="10.0.1.224:5000"
TAG="latest"

echo "Building Docker image..."
docker build -t ${IMAGE_NAME}:${TAG} .

echo "Tagging image for registry..."
docker tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}

echo "Pushing image to registry ${REGISTRY}..."
docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}

echo "Build and push completed successfully!"
echo "Image: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
