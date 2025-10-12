#!/bin/bash

# ==============================================================================
# L1 Integrated Container - Automated Build Script (Embedded Model)
# ==============================================================================
# This script automates the build process by:
# 1. Copying the Mistral GGUF model from system path to build context
# 2. Building Docker image with embedded model (~10GB)
# 3. Pushing to container registry
# 4. Cleaning up temporary files
#
# Usage: ./build-embedded.sh
# ==============================================================================

set -e  # Exit on any error

# Configuration
MODEL_SOURCE="/home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
MODEL_DEST="./mistral-7b-instruct-v0.2.Q4_K_M.gguf"
IMAGE_NAME="10.0.1.224:5000/l1-integrated:latest"
DOCKERFILE="Dockerfile.tslam"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  L1 Integrated - Automated Build${NC}"
echo -e "${BLUE}  (Embedded Model Architecture)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Verify model source exists
log_info "Step 1/5: Verifying model file..."
if [ ! -f "$MODEL_SOURCE" ]; then
    log_error "Model file not found at: $MODEL_SOURCE"
    log_error "Please ensure the Mistral GGUF model is available at the expected path"
    exit 1
fi

MODEL_SIZE=$(du -h "$MODEL_SOURCE" | cut -f1)
log_success "Model found: $MODEL_SIZE at $MODEL_SOURCE"

# Step 2: Copy model to build context
log_info "Step 2/5: Copying model to build context..."
if [ -f "$MODEL_DEST" ]; then
    log_warning "Model already exists in build context, removing old copy..."
    rm -f "$MODEL_DEST"
fi

cp "$MODEL_SOURCE" "$MODEL_DEST"
log_success "Model copied to build context"

# Step 3: Build Docker image
log_info "Step 3/5: Building Docker image (this may take 5-10 minutes)..."
log_info "Image will be ~10GB with embedded model"
echo ""

if podman build --no-cache -t "$IMAGE_NAME" -f "$DOCKERFILE" .; then
    log_success "Docker image built successfully"
else
    log_error "Docker build failed"
    log_warning "Cleaning up model copy..."
    rm -f "$MODEL_DEST"
    exit 1
fi

# Step 4: Push to registry
log_info "Step 4/5: Pushing image to registry..."
if podman push "$IMAGE_NAME"; then
    log_success "Image pushed to $IMAGE_NAME"
else
    log_error "Failed to push image to registry"
    log_warning "Cleaning up model copy..."
    rm -f "$MODEL_DEST"
    exit 1
fi

# Step 5: Cleanup
log_info "Step 5/5: Cleaning up temporary files..."
rm -f "$MODEL_DEST"
log_success "Build context cleaned"

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Image: ${BLUE}$IMAGE_NAME${NC}"
echo -e "Size:  ${BLUE}~10GB (with embedded 4.1GB model)${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Deploy: ${YELLOW}oc apply -f l1-pod-embedded.yaml${NC}"
echo -e "  2. Monitor: ${YELLOW}oc logs -f l1-integrated -n l1-app-ai${NC}"
echo ""
