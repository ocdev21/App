#!/bin/bash

# Simple TSLAM CPU Deployment Script
echo "🚀 Deploying TSLAM-4B CPU Inference (Simple Version)"
echo "=================================================="
echo "This will deploy vLLM with CPU inference for streaming responses"
echo ""

# Clean up any existing deployments
echo "Step 1: Cleaning Up"
echo "=================="
oc delete deployment tslam-vllm-deployment -n l1-app-ai 2>/dev/null || echo "No existing deployment"
oc delete deployment tslam-vllm-cpu-deployment -n l1-app-ai 2>/dev/null || echo "No existing CPU deployment"

echo "✅ Cleanup complete"
echo ""

# Deploy simple CPU version
echo "Step 2: Deploying Simple CPU vLLM"
echo "================================"
oc apply -f tslam-cpu-simple.yaml

echo "✅ Deployment created"
echo ""

# Wait for PVC
echo "Step 3: Waiting for Storage"
echo "========================="
echo "Waiting for PVC to be bound..."
timeout=120
counter=0
while [ $counter -lt $timeout ]; do
    PVC_STATUS=$(oc get pvc l1-ml-models-pvc -n l1-app-ai -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$PVC_STATUS" = "Bound" ]; then
        echo "✅ Storage ready"
        break
    fi
    echo "⏳ PVC status: $PVC_STATUS"
    sleep 5
    counter=$((counter + 5))
done

if [ $counter -ge $timeout ]; then
    echo "❌ Storage timeout"
    exit 1
fi

# Model upload instructions
echo ""
echo "Step 4: Model Upload"
echo "=================="
echo "📁 Upload your TSLAM-4B model:"
echo ""
echo "1. Access uploader pod:"
echo "   oc exec -it tslam-model-uploader -n l1-app-ai -- sh"
echo ""
echo "2. Your model should be copied to: /models/tslam-4b/"
echo "   (From your local: /home/cloud-user/pjoe/model)"
echo ""
echo "3. Verify model files:"
echo "   ls -la /models/tslam-4b/"
echo ""

# Monitor deployment
echo "Step 5: Monitoring Deployment"
echo "============================"
echo "Deployment status:"
oc get deployment tslam-vllm-deployment -n l1-app-ai

echo ""
echo "Pod status:"
oc get pods -n l1-app-ai

echo ""
echo "📊 Monitor with:"
echo "- Pods: oc get pods -n l1-app-ai -w"
echo "- Logs: oc logs -f deployment/tslam-vllm-deployment -n l1-app-ai"
echo "- Service: oc get svc tslam-vllm-service -n l1-app-ai"
echo ""
echo "🎯 Expected Timeline:"
echo "- Model upload: Manual (you do this)"
echo "- vLLM startup: 3-5 minutes after model upload"
echo "- Service ready: Total ~5-10 minutes"
echo ""
echo "✅ Once running, your L1 dashboard will get streaming TSLAM responses!"