#!/bin/bash

# Deploy TSLAM with Direct Model Access
echo "🚀 Deploying TSLAM-4B CPU Inference (Direct Access)"
echo "================================================="
echo "Using model directly from: /home/cloud-user/pjoe/model"
echo ""

# Clean up any existing deployments
echo "Step 1: Cleaning Up"
echo "=================="
oc delete deployment tslam-vllm-deployment -n l1-app-ai 2>/dev/null || echo "No existing deployment"
oc delete pod tslam-model-uploader -n l1-app-ai 2>/dev/null || echo "No uploader pod"
oc delete pvc l1-ml-models-pvc -n l1-app-ai 2>/dev/null || echo "No existing PVC"

echo "✅ Cleanup complete"
echo ""

# Deploy direct access version
echo "Step 2: Deploying TSLAM with Direct Model Access"
echo "=============================================="
oc apply -f tslam-cpu-direct.yaml

echo "✅ Deployment created"
echo ""

# Monitor deployment
echo "Step 3: Monitoring TSLAM Startup"
echo "==============================="
echo "Deployment status:"
oc get deployment tslam-vllm-deployment -n l1-app-ai

echo ""
echo "Pod status:"
oc get pods -n l1-app-ai

echo ""
echo "Service status:"
oc get svc tslam-vllm-service -n l1-app-ai

echo ""
echo "📊 Monitor Progress:"
echo "- Watch pods: oc get pods -n l1-app-ai -w"
echo "- View logs: oc logs -f deployment/tslam-vllm-deployment -n l1-app-ai"
echo "- Check health: oc exec -it <pod-name> -n l1-app-ai -- curl localhost:8000/health"
echo ""
echo "🎯 Expected Timeline:"
echo "- Pod startup: 1-2 minutes"
echo "- Model loading: 3-5 minutes (CPU inference)"
echo "- Service ready: Total ~5-7 minutes"
echo ""
echo "✅ Once ready, your L1 dashboard will stream real TSLAM-4B responses!"
echo ""
echo "🔍 Test streaming once ready:"
echo "Your RemoteTSLAMClient will connect to: tslam-vllm-service.l1-app-ai.svc.cluster.local:8000"