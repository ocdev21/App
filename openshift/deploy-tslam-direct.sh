#!/bin/bash

# Deploy TSLAM with Direct Model Access
echo "🚀 Deploying TSLAM-4B CPU Inference (PVC Storage)"
echo "==============================================="
echo "Copying model from: /home/cloud-user/pjoe/model to PVC"
echo ""

# Clean up any existing deployments
echo "Step 1: Cleaning Up"
echo "=================="
oc delete deployment tslam-vllm-deployment -n l1-app-ai 2>/dev/null || echo "No existing deployment"
oc delete pod tslam-model-uploader -n l1-app-ai 2>/dev/null || echo "No uploader pod"
oc delete pvc tslam-model-storage-pvc -n l1-app-ai 2>/dev/null || echo "No existing PVC"

echo "✅ Cleanup complete"
echo ""

# Deploy PVC version
echo "Step 2: Deploying TSLAM with PVC Storage"
echo "======================================"
oc apply -f tslam-cpu-direct.yaml

echo "✅ Deployment created"
echo ""

# Wait for PVC to be bound
echo "Step 3: Waiting for PVC to Bind"
echo "============================"
echo "Waiting for PVC to be bound..."
timeout=120
counter=0
while [ $counter -lt $timeout ]; do
    PVC_STATUS=$(oc get pvc tslam-model-storage-pvc -n l1-app-ai -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$PVC_STATUS" = "Bound" ]; then
        echo "✅ PVC bound successfully"
        break
    fi
    echo "⏳ PVC status: $PVC_STATUS"
    sleep 5
    counter=$((counter + 5))
done

if [ $counter -ge $timeout ]; then
    echo "❌ PVC binding timeout"
    exit 1
fi

# Copy model to PVC
echo ""
echo "Step 4: Copying Model to PVC"
echo "========================="
echo "Waiting for uploader pod to be ready..."
sleep 10

echo "Copying TSLAM-4B model from host to PVC..."
oc exec tslam-model-uploader -n l1-app-ai -- sh -c "cp -r /host-model/* /models/ && echo 'Model copy completed'"

echo "Verifying model files in PVC:"
oc exec tslam-model-uploader -n l1-app-ai -- ls -la /models/

echo "✅ Model ready in PVC"

# Monitor deployment
echo ""
echo "Step 5: Monitoring TSLAM Startup"
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
echo ""
echo "📁 Model Location: /models/tslam-4b (in PVC)"
echo "✅ Ready for streaming L1 network analysis!"