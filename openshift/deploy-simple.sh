#!/bin/bash

echo "Deploying Ultra-Simple TSLAM Service"
echo "===================================="

PROJECT_NAME="l1-app-ai"

# Complete cleanup first
echo "1. Complete cleanup of all TSLAM resources..."
oc delete deployment tslam-vllm-deployment -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-transformers-deployment -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-vllm-simple -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-simple -n $PROJECT_NAME --ignore-not-found=true

oc delete service tslam-vllm-service -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-transformers-service -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-simple-service -n $PROJECT_NAME --ignore-not-found=true

oc delete configmap tslam-inference-code -n $PROJECT_NAME --ignore-not-found=true

echo "2. Waiting for cleanup to complete..."
sleep 10

echo "3. Deploying ultra-simple working solution..."
oc apply -f tslam-simple-working.yaml

echo "4. Waiting for deployment..."
oc rollout status deployment/tslam-simple -n $PROJECT_NAME --timeout=120s

echo "5. Checking status..."
oc get pods -l app=tslam-simple -n $PROJECT_NAME
oc get service tslam-simple-service -n $PROJECT_NAME

echo ""
echo "✅ Simple TSLAM deployment complete!"
echo ""
echo "To test:"
echo "  1. Port forward: oc port-forward svc/tslam-simple-service 8000:8000 -n $PROJECT_NAME"
echo "  2. Health check: curl http://localhost:8000/health"
echo "  3. Test chat: curl -X POST http://localhost:8000/v1/chat/completions \\"
echo "                     -H 'Content-Type: application/json' \\"
echo "                     -d '{\"model\": \"tslam-4b\", \"messages\": [{\"role\": \"user\", \"content\": \"Analyze packet loss\"}]}'"
echo ""
echo "Logs: oc logs -f deployment/tslam-simple -n $PROJECT_NAME"