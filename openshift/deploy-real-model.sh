#!/bin/bash

echo "Deploying TSLAM Real Model Service with PVC Mount"
echo "=================================================="

PROJECT_NAME="l1-app-ai"

# Clean up previous deployments
echo "1. Cleaning up previous deployments..."
oc delete deployment tslam-simple -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-simple-service -n $PROJECT_NAME --ignore-not-found=true
oc delete configmap tslam-inference-code -n $PROJECT_NAME --ignore-not-found=true

echo "2. Deploying TSLAM real model service..."
oc apply -f tslam-real-model-deployment.yaml

echo "3. Waiting for deployment to be ready..."
oc rollout status deployment/tslam-real-model -n $PROJECT_NAME --timeout=600s

echo "4. Checking PVC mount and model files..."
oc exec deployment/tslam-real-model -n $PROJECT_NAME -- ls -la /models/

echo "5. Checking pod status..."
oc get pods -l app=tslam-real-model -n $PROJECT_NAME

echo "6. Displaying service information..."
oc get service tslam-real-model-service -n $PROJECT_NAME

echo ""
echo "🚀 TSLAM Real Model deployment complete!"
echo ""
echo "To test using service name (within cluster):"
echo "  1. Health check: oc exec -it deployment/tslam-real-model -n $PROJECT_NAME -- curl http://tslam-real-model-service:8000/health"
echo "  2. Test real model: oc exec -it deployment/tslam-real-model -n $PROJECT_NAME -- curl -X POST http://tslam-real-model-service:8000/v1/chat/completions \\"
echo "                           -H 'Content-Type: application/json' \\"
echo "                           -d '{\"model\": \"tslam-4b\", \"messages\": [{\"role\": \"user\", \"content\": \"Analyze L1 packet loss on cell tower\"}]}'"
echo ""
echo "To check model loading: oc logs -f deployment/tslam-real-model -n $PROJECT_NAME"
echo ""
echo "Note: The service will attempt to load your TSLAM-4B model from /models/tslam-4b"
echo "      If the model files are missing or corrupted, it will fallback to L1 knowledge base"