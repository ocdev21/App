#!/bin/bash
# Build Test Script - Run this on your machine with Docker

echo "Testing L1 App Docker Builds..."

echo "Step 1: Testing Minimal Build..."
docker build -f Dockerfile.minimal -t l1-app-minimal:latest . --no-cache || {
    echo "ERROR: Minimal build failed"
    exit 1
}

echo "Step 2: Testing Fixed Build..."  
docker build -f Dockerfile.fixed -t l1-app-fixed:latest . --progress=plain --no-cache || {
    echo "ERROR: Fixed build failed"
    exit 1
}

echo "All builds successful!"
echo "You can now deploy using:"
echo "   docker tag l1-app-fixed:latest <your-registry>/l1-app-ai/l1-app-production:latest"
echo "   docker push <your-registry>/l1-app-ai/l1-app-production:latest"