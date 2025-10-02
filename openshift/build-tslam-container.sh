#!/bin/bash

echo "Mistral GGUF Container Build Script"
echo "===================================="
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
IMAGE_NAME="tslam-with-model"
IMAGE_TAG="latest"
REGISTRY="10.0.1.224:5000"

# Check if model source exists
if [ ! -f "$MODEL_SOURCE" ]; then
    echo "ERROR: Model file $MODEL_SOURCE does not exist!"
    exit 1
fi

echo "Step 1: Preparing build context..."
mkdir -p build-context
cp "$MODEL_SOURCE" build-context/mistral-7b-instruct-v0.2.Q4_K_M.gguf
cp Dockerfile.tslam build-context/Dockerfile
cp tslam-container-server.py build-context/

echo "Step 2: Checking model file..."
MODEL_SIZE=$(du -h "build-context/mistral-7b-instruct-v0.2.Q4_K_M.gguf" | cut -f1)
echo "   Model file size: $MODEL_SIZE"

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
echo "Next step: Deploy with 'oc apply -f tslam-pod.yaml'"

cd ..
