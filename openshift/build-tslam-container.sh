#!/bin/bash

echo "Mistral Transformers Container Build Script"
echo "============================================"
echo ""

# Check if we should download Mistral or use local copy
if [ -d "/home/cloud-user/pjoe/model/mistral7b-hf" ]; then
    MODEL_SOURCE="/home/cloud-user/pjoe/model/mistral7b-hf"
    echo "Using local Mistral model from: $MODEL_SOURCE"
else
    echo "No local Mistral HuggingFace model found."
    echo "Container will download from HuggingFace on first run."
    MODEL_SOURCE=""
fi

IMAGE_NAME="tslam-with-model"
IMAGE_TAG="latest"
REGISTRY="10.0.1.224:5000"

echo "Step 1: Preparing build context..."
mkdir -p build-context

if [ -n "$MODEL_SOURCE" ]; then
    echo "Copying Mistral model files..."
    mkdir -p build-context/mistral-model
    cp -r $MODEL_SOURCE/* build-context/mistral-model/
    MODEL_FILES=$(find build-context/mistral-model -type f | wc -l)
    echo "   Copied $MODEL_FILES model files"
else
    mkdir -p build-context/mistral-model
    echo "   Model will be downloaded at runtime"
fi

cp Dockerfile.tslam build-context/Dockerfile
cp mistral-inference-server.py build-context/

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
echo "✅ Image ready: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Next: oc apply -f tslam-pod.yaml"

cd ..
