#!/bin/bash

echo "Mistral GGUF Container Build Script"
echo "===================================="
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
IMAGE_NAME="tslam-with-model"
IMAGE_TAG="latest"
REGISTRY="10.0.1.224:5000"

# Check if GGUF file exists
if [ ! -f "$MODEL_SOURCE" ]; then
    echo "ERROR: GGUF model file not found: $MODEL_SOURCE"
    echo ""
    echo "Please verify the path to your Mistral GGUF file"
    exit 1
fi

MODEL_SIZE=$(du -h "$MODEL_SOURCE" | cut -f1)
echo "Found GGUF model: $MODEL_SIZE"

echo ""
echo "Step 1: Preparing build context..."
mkdir -p build-context

cp "$MODEL_SOURCE" build-context/mistral-7b-instruct-v0.2.Q4_K_M.gguf
echo "   Copied GGUF model file"

cp Dockerfile.tslam build-context/Dockerfile
cp gguf-inference-server.py build-context/

echo ""
echo "Step 2: Building container image..."
echo "   Image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""

cd build-context

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
echo "Step 3: Pushing to registry..."
$BUILDER push $REGISTRY/$IMAGE_NAME:$IMAGE_TAG

if [ $? -ne 0 ]; then
    echo "ERROR: Push failed!"
    exit 1
fi

echo ""
echo "Build Complete: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Next: oc apply -f tslam-pod.yaml"

cd ..
