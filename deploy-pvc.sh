#!/bin/bash

# Deploy PVC Setup for ML Models Storage
echo "🚀 Deploying PVC setup for ML models storage..."

# Apply the OpenShift deployment with ML Models PVC
echo "📦 Creating ML Models PVC and updating deployment..."
oc apply -f openshift/l1-app-openshift-ai-deployment.yaml

# Check PVC status
echo "✅ Checking PVC status..."
oc get pvc l1-ml-models-pvc -n l1-app-ai

# Check deployment status
echo "📊 Checking deployment status..."
oc get deployment l1-troubleshooting-ai -n l1-app-ai

# Watch rollout
echo "🔄 Watching rollout status..."
oc rollout status deployment/l1-troubleshooting-ai -n l1-app-ai

echo "✅ Deployment complete!"