#!/bin/bash

# Deploy PVC Setup for ML Models Storage
echo "🚀 Deploying PVC setup for ML models storage..."

# Apply the production pod deployment with ML Models PVC
echo "📦 Creating ML Models PVC and deploying production pod..."
kubectl apply -f k8s-pod-production.yaml

# Check PVC status
echo "✅ Checking PVC status..."
kubectl get pvc l1-ml-models-pvc -n l1-app-ai

# Check pod status
echo "📊 Checking pod status..."
kubectl get pod l1-prod-app -n l1-app-ai

# Check service status
echo "🌐 Checking NodePort service status..."
kubectl get service l1-prod-app-service -n l1-app-ai

# Wait for pod to be ready
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/l1-prod-app -n l1-app-ai --timeout=300s

echo "✅ Deployment complete!"
echo "🔗 Access via NodePort: http://your-cluster-ip:30542"