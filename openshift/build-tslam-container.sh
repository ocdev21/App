#!/bin/bash

echo "TSLAM Container Build Script"
echo "============================"
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model"
IMAGE_NAME="tslam-with-model"
IMAGE_TAG="latest"
REGISTRY="quay.io"  # Change this to your registry
REGISTRY_USER="your-username"  # Change this to your username

# Check if model source exists
if [ ! -d "$MODEL_SOURCE" ]; then
    echo "ERROR: Model source directory $MODEL_SOURCE does not exist!"
    exit 1
fi

echo "Step 1: Preparing build context..."
mkdir -p build-context/model
cp -r $MODEL_SOURCE/* build-context/model/
cp Dockerfile.tslam build-context/Dockerfile
cp tslam-container-server.py build-context/

echo "Step 2: Checking model files..."
MODEL_FILE_COUNT=$(find build-context/model -type f | wc -l)
echo "   Model files to include: $MODEL_FILE_COUNT"
ls -lh build-context/model/ | head -10

echo ""
echo "Step 3: Building container image..."
echo "   Image: $REGISTRY/$REGISTRY_USER/$IMAGE_NAME:$IMAGE_TAG"
echo ""

cd build-context

# Build with podman (or docker if you prefer)
if command -v podman &> /dev/null; then
    BUILDER="podman"
elif command -v docker &> /dev/null; then
    BUILDER="docker"
else
    echo "ERROR: Neither podman nor docker found!"
    exit 1
fi

echo "Using builder: $BUILDER"
echo ""

$BUILDER build -t $REGISTRY/$REGISTRY_USER/$IMAGE_NAME:$IMAGE_TAG . --no-cache

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed!"
    exit 1
fi

echo ""
echo "Step 4: Container image built successfully!"
echo ""
echo "Step 5: Pushing to registry..."
echo "   (Make sure you're logged in: $BUILDER login $REGISTRY)"
echo ""

# Uncomment the next line to auto-push
# $BUILDER push $REGISTRY/$REGISTRY_USER/$IMAGE_NAME:$IMAGE_TAG

echo "To push manually, run:"
echo "   $BUILDER push $REGISTRY/$REGISTRY_USER/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "After pushing, update tslam-container-deployment.yaml with your image path"
echo "Then deploy with: ./deploy-container.sh"

cd ..
