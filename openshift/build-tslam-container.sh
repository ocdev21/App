#!/bin/bash

echo "Mistral HF Container Build Script"
echo "=================================="
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model/mistral7b-hf"
IMAGE_NAME="tslam-with-model"
IMAGE_TAG="latest"
REGISTRY="10.0.1.224:5000"

# Check if model directory exists
if [ ! -d "$MODEL_SOURCE" ]; then
    echo "ERROR: Model directory $MODEL_SOURCE does not exist!"
    echo ""
    echo "Please download Mistral-7B-Instruct-v0.2 first:"
    echo "  huggingface-cli download mistralai/Mistral-7B-Instruct-v0.2 \\"
    echo "    --local-dir $MODEL_SOURCE \\"
    echo "    --local-dir-use-symlinks False"
    exit 1
fi

# Check for required files
echo "Checking model files..."
REQUIRED_FILES=("config.json" "tokenizer.json" "tokenizer_config.json")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$MODEL_SOURCE/$file" ]; then
        echo "ERROR: Missing $file in model directory"
        exit 1
    fi
done

echo "Step 1: Preparing build context..."
mkdir -p build-context/mistral7b-hf
cp -r $MODEL_SOURCE/* build-context/mistral7b-hf/

MODEL_FILES=$(find build-context/mistral7b-hf -type f | wc -l)
echo "   Copied $MODEL_FILES model files"

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
