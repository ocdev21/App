#!/bin/bash

echo "Pulling Prometheus image from quay.io (alternative to Docker Hub)..."
docker pull quay.io/prometheus/prometheus:v2.48.0

echo "Tagging for local registry..."
docker tag quay.io/prometheus/prometheus:v2.48.0 10.0.1.224:5000/prometheus:v2.48.0

echo "Pushing to local registry (10.0.1.224:5000)..."
docker push 10.0.1.224:5000/prometheus:v2.48.0

echo ""
echo "✓ Prometheus image successfully pushed to 10.0.1.224:5000"
echo ""
echo "Now you can deploy with:"
echo "  kubectl apply -f prometheus-monitoring.yaml"
