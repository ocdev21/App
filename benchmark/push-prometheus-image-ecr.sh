#!/bin/bash

echo "Pulling Prometheus image from Amazon ECR Public (mirror of quay.io)..."
docker pull public.ecr.aws/h4m7v9o4/quay.io/prometheus/prometheus:v2.48.0

echo "Tagging for local registry..."
docker tag public.ecr.aws/h4m7v9o4/quay.io/prometheus/prometheus:v2.48.0 10.0.1.224:5000/prometheus:v2.48.0

echo "Pushing to local registry (10.0.1.224:5000)..."
docker push 10.0.1.224:5000/prometheus:v2.48.0

echo ""
echo "✓ Prometheus image successfully pushed to 10.0.1.224:5000"
echo ""
echo "Now you can deploy with:"
echo "  kubectl apply -f prometheus-monitoring.yaml"
