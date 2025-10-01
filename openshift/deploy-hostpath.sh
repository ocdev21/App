#!/bin/bash

echo "Deploying TSLAM with HostPath Model Copy"
echo "======================================="

PROJECT_NAME="l1-app-ai"

# Clean up previous deployments
echo "1. Cleaning up previous deployments..."
oc delete deployment tslam-real-model -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-simple -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-real-model-service -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-simple-service -n $PROJECT_NAME --ignore-not-found=true
oc delete configmap tslam-real-inference-code -n $PROJECT_NAME --ignore-not-found=true
oc delete configmap tslam-inference-code -n $PROJECT_NAME --ignore-not-found=true

echo "2. Deploying TSLAM hostpath service..."
oc apply -f tslam-hostpath-deployment.yaml

echo "3. Waiting for init container to copy model files..."
echo "   (This may take a few minutes depending on model size)"

# Monitor init container progress
echo "4. Checking init container logs..."
sleep 10

# Get pod name
POD_NAME=$(oc get pods -l app=tslam-hostpath-model -n $PROJECT_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$POD_NAME" ]; then
    echo "Pod name: $POD_NAME"
    echo "Init container logs:"
    oc logs $POD_NAME -c model-copier -n $PROJECT_NAME || echo "Init container still running..."
else
    echo "Pod not found yet, waiting..."
fi

echo "5. Waiting for main deployment to be ready..."
oc rollout status deployment/tslam-hostpath-model -n $PROJECT_NAME --timeout=600s

echo "6. Checking final status..."
oc get pods -l app=tslam-hostpath-model -n $PROJECT_NAME
oc get service tslam-hostpath-service -n $PROJECT_NAME

echo ""
echo "🚀 TSLAM HostPath deployment complete!"
echo ""
echo "To test using service name:"
echo "  1. Health check: oc exec -it deployment/tslam-hostpath-model -n $PROJECT_NAME -- curl http://tslam-hostpath-service:8000/health"
echo "  2. Test TSLAM model: oc exec -it deployment/tslam-hostpath-model -n $PROJECT_NAME -- curl -X POST http://tslam-hostpath-service:8000/v1/chat/completions \\"
echo "                            -H 'Content-Type: application/json' \\"
echo "                            -d '{\"model\": \"tslam-4b\", \"messages\": [{\"role\": \"user\", \"content\": \"Analyze L1 signal degradation on fiber link\"}]}'"
echo ""
echo "To check model loading: oc logs -f deployment/tslam-hostpath-model -n $PROJECT_NAME"
echo ""
echo "Note: Init container copies from /home/cloud-user/pjoe/model to /models in the pod"
echo "      If source directory is empty, it creates placeholder files for testing"