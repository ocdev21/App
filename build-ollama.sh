#!/bin/bash

set -e

IMAGE_NAME="ollama-mistral"
IMAGE_TAG="latest"
REGISTRY="localhost:5000"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "========================================"
echo "Building Ollama with Mistral Model"
echo "========================================"
echo ""
echo "⚠️  INFO: This build will:"
echo "   - Use local Mistral GGUF file"
echo "   - Take 2-5 minutes to build"
echo "   - Create a large Docker image (~5-6GB)"
echo ""
echo "📁 Checking for Mistral GGUF file..."
echo ""

GGUF_FILE="mistral-7b-instruct-v0.2.Q4_K_M.gguf"
SOURCE_PATH="/home/siddharth-sin/mistral7b/${GGUF_FILE}"

# Check if GGUF file exists in current directory
if [ ! -f "${GGUF_FILE}" ]; then
    echo "⚠️  GGUF file not found in current directory"
    
    # Check if source file exists
    if [ -f "${SOURCE_PATH}" ]; then
        echo "✓ Found GGUF at: ${SOURCE_PATH}"
        echo "Creating symlink..."
        ln -s "${SOURCE_PATH}" "${GGUF_FILE}"
        echo "✓ Symlink created successfully"
    else
        echo "❌ ERROR: GGUF file not found at: ${SOURCE_PATH}"
        echo ""
        echo "Please ensure the Mistral GGUF file exists at the expected location."
        exit 1
    fi
else
    echo "✓ GGUF file found in current directory"
fi
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Build cancelled."
    exit 1
fi

echo "Building image: ${FULL_IMAGE}"
docker build -f Dockerfile-ollama -t ${IMAGE_NAME}:${IMAGE_TAG} .

echo "Tagging image for registry..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE}

echo "Pushing image to registry: ${REGISTRY}"
docker push ${FULL_IMAGE}

echo "========================================"
echo "Build and push completed successfully!"
echo "Image: ${FULL_IMAGE}"
echo "Model: Mistral (pre-downloaded)"
echo "========================================"

echo ""
echo "To deploy Ollama, run:"
echo "  oc create namespace ricxapp  # (if not exists)"
echo "  oc apply -f kubernetes-ollama.yaml"
echo ""
echo "To check deployment status:"
echo "  oc get pods -n ricxapp"
echo "  oc logs -f deployment/ollama-service -n ricxapp"
echo ""
echo "To test Ollama:"
echo "  oc exec -it deployment/ollama-service -n ricxapp -- ollama list"
 