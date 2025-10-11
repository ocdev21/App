#!/bin/bash

echo "=========================================="
echo "L1 Integrated Container Build Script"
echo "Frontend + Backend + AI Inference"
echo "=========================================="
echo ""
echo "NOTE: Model will be loaded from PVC at /pvc/models/mistral.gguf"
echo "      Use 'kubectl cp' to copy model to PVC (see BUILD_INSTRUCTIONS.md)"
echo ""

IMAGE_NAME="l1-integrated"
IMAGE_TAG="latest"
REGISTRY="10.0.1.224:5000"

echo "Step 1: Preparing build context..."
rm -rf build-context
mkdir -p build-context

# Copy entire parent directory (excluding node_modules and build artifacts)
echo "  Copying L1 application files from parent directory..."
rsync -a --exclude='node_modules' \
         --exclude='dist' \
         --exclude='build' \
         --exclude='.git' \
         --exclude='.local' \
         --exclude='.config' \
         --exclude='.cache' \
         --exclude='.venv' \
         --exclude='__pycache__' \
         --exclude='*.pyc' \
         --exclude='build-context' \
         --exclude='*.log' \
         ../ build-context/

# Copy Docker files from current directory
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

$BUILDER build -t $REGISTRY/$IMAGE_NAME:$IMAGE_TAG .

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
echo "Next steps:"
echo "  1. Delete old pod: oc delete pod tslam-container -n l1-app-ai --force"
echo "  2. Deploy: oc apply -f tslam-pod.yaml"
echo "  3. Check logs: oc logs -f l1-integrated -n l1-app-ai"

cd ..
