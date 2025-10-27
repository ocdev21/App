#!/bin/bash

set -e

IMAGE_NAME="ricxapp-superapp"
IMAGE_TAG="latest"
REGISTRY="localhost:5000"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "========================================"
echo "Building Docker image for SuperApp"
echo "========================================"

echo "Building image: ${FULL_IMAGE}"
docker build -f Dockerfile-superapp -t ${IMAGE_NAME}:${IMAGE_TAG} .

echo "Tagging image for registry..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE}

echo "Pushing image to registry: ${REGISTRY}"
docker push ${FULL_IMAGE}

echo "========================================"
echo "Build and push completed successfully!"
echo "Image: ${FULL_IMAGE}"
echo "========================================"

echo ""
echo "To deploy to OpenShift, run:"
echo "  oc create namespace ricxapp  # (if not exists)"
echo "  oc apply -f kubernetes-superapp.yaml"
echo ""
echo "To check deployment status:"
echo "  oc get pods -n ricxapp"
echo "  oc logs -f deployment/ricxapp-superapp -n ricxapp"
