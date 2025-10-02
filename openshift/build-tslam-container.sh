#!/bin/bash

echo "=========================================="
echo "L1 Integrated Container Build Script"
echo "Frontend + Backend + AI Inference"
echo "=========================================="
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
IMAGE_NAME="l1-integrated"
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

# Copy project files
echo "  Copying L1 application files..."
cp -r ../package*.json build-context/ 2>/dev/null || true
cp -r ../tsconfig.json build-context/ 2>/dev/null || true
cp -r ../vite.config.ts build-context/ 2>/dev/null || true
cp -r ../tailwind.config.ts build-context/ 2>/dev/null || true
cp -r ../postcss.config.js build-context/ 2>/dev/null || true
cp -r ../index.html build-context/ 2>/dev/null || true
cp -r ../client build-context/ 2>/dev/null || true
cp -r ../server build-context/ 2>/dev/null || true
cp -r ../db build-context/ 2>/dev/null || true
cp -r ../shared build-context/ 2>/dev/null || true

# Copy GGUF model
echo "  Copying GGUF model..."
cp "$MODEL_SOURCE" build-context/mistral-7b-instruct-v0.2.Q4_K_M.gguf

# Copy Docker files
echo "  Copying Dockerfile and scripts..."
cp Dockerfile.tslam build-context/Dockerfile
cp gguf-inference-server.py build-context/
cp start-services.sh build-context/

echo "  Build context prepared"

echo ""
echo "Step 2: Building integrated container image..."
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
echo "=========================================="
echo "Build Complete!"
echo "Image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Services included:"
echo "  - L1 Web Application (port 5000)"
echo "  - AI Inference Server (port 8000)"
echo "=========================================="
echo ""
echo "Next: Update tslam-pod.yaml with new image name and deploy"

cd ..
