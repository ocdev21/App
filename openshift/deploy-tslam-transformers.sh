#!/bin/bash

echo "Deploying TSLAM Transformers-based Inference (No vLLM)"
echo "========================================================"

PROJECT_NAME="l1-app-ai"

# Clean up old vLLM deployments
echo "1. Cleaning up old vLLM deployments..."
oc delete deployment tslam-vllm-deployment -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-vllm-service -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-vllm-simple -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-simple-service -n $PROJECT_NAME --ignore-not-found=true

echo "2. Deploying new transformers-based solution..."
oc apply -f tslam-transformers-deployment.yaml

echo "3. Waiting for deployment to be ready..."
oc rollout status deployment/tslam-transformers-deployment -n $PROJECT_NAME --timeout=300s

echo "4. Checking pod status..."
oc get pods -l app=tslam-transformers -n $PROJECT_NAME

echo "5. Displaying service information..."
oc get service tslam-transformers-service -n $PROJECT_NAME

echo ""
echo "🚀 TSLAM Transformers deployment complete!"
echo ""
echo "To test the service:"
echo "  1. Port forward: oc port-forward svc/tslam-transformers-service 8000:8000 -n $PROJECT_NAME"
echo "  2. Health check: curl http://localhost:8000/health"
echo "  3. Test chat: curl -X POST http://localhost:8000/v1/chat/completions \\"
echo "                     -H 'Content-Type: application/json' \\"
echo "                     -d '{\"model\": \"tslam-4b\", \"messages\": [{\"role\": \"user\", \"content\": \"Analyze packet loss\"}]}'"
echo ""
echo "To check logs: oc logs -f deployment/tslam-transformers-deployment -n $PROJECT_NAME"