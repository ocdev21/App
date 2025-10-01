#!/bin/bash

echo "TSLAM Container Build Script"
echo "============================"
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model"
IMAGE_NAME="tslam-with-model"
IMAGE_TAG="latest"
REGISTRY="10.0.1.224:5000"

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
echo "   Image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
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

$BUILDER build -t $REGISTRY/$IMAGE_NAME:$IMAGE_TAG . --no-cache

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed!"
    exit 1
fi

echo ""
echo "Step 4: Container image built successfully!"
echo ""
echo "Step 5: Pushing to local registry..."
$BUILDER push $REGISTRY/$IMAGE_NAME:$IMAGE_TAG

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to push to $REGISTRY"
    echo "Make sure local registry is running at $REGISTRY"
    exit 1
fi

echo ""
echo "✅ Image pushed successfully to $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Next step: Deploy with ./deploy-pod.sh"

cd ..
