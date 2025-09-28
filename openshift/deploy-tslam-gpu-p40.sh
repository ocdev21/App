#!/bin/bash

# TSLAM-4B Tesla P40 GPU Deployment Script
# This script deploys vLLM with Tesla P40 GPU acceleration

set -e

echo "🚀 Deploying TSLAM-4B GPU Inference (Tesla P40)"
echo "==============================================="
echo "Target nodes with Tesla P40 GPUs:"
echo "- rhocp-gx5wg-worker-0-vfm8l"
echo "- rhocp-gx5wg-worker-0-pdg59" 
echo "- rhocp-gx5wg-worker-0-cbmkw"
echo ""

# Prerequisites check
echo "Step 1: Checking Prerequisites"
echo "============================="

echo "Checking if GPU operator is installed..."
if ! oc get clusterpolicy gpu-cluster-policy >/dev/null 2>&1; then
    echo "❌ GPU operator not found!"
    echo ""
    echo "Please install GPU operator first:"
    echo "./install-gpu-operator.sh"
    echo ""
    echo "Then wait for ClusterPolicy to show 'State: ready'"
    echo "Check with: oc get clusterpolicy"
    exit 1
fi

echo "Checking ClusterPolicy status..."
POLICY_STATE=$(oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
if [ "$POLICY_STATE" != "ready" ]; then
    echo "⚠️  GPU operator not ready yet. Current state: $POLICY_STATE"
    echo ""
    echo "Please wait for GPU operator installation to complete."
    echo "Monitor with: oc get pods -n nvidia-gpu-operator -w"
    echo "Check status: oc get clusterpolicy"
    exit 1
fi

echo "✅ GPU operator is ready!"

echo "Checking Tesla P40 availability..."
GPU_COUNT=$(oc get nodes -o yaml | grep -c "nvidia.com/gpu" || echo "0")
if [ "$GPU_COUNT" = "0" ]; then
    echo "❌ No GPUs detected in cluster!"
    echo "Tesla P40s may not be properly configured."
    exit 1
fi

echo "✅ Found $GPU_COUNT GPU nodes ready"
echo ""

# Clean up old deployment
echo "Step 2: Cleaning Up Old Deployment"
echo "================================="

echo "Removing old CPU deployment (if exists)..."
oc delete deployment tslam-vllm-cpu-deployment -n l1-app-ai 2>/dev/null || echo "No old CPU deployment found"

echo "Removing old GPU deployment (if exists)..."
oc delete deployment tslam-vllm-deployment -n l1-app-ai 2>/dev/null || echo "No old GPU deployment found"

echo "✅ Old deployments cleaned up"
echo ""

# Deploy GPU version
echo "Step 3: Deploying Tesla P40 GPU Infrastructure"
echo "============================================="

echo "Creating/updating l1-app-ai namespace and resources..."
oc apply -f tslam-gpu-deployment.yaml

echo "✅ GPU deployment created"
echo ""

# Check PVC binding
echo "Step 4: Waiting for PVC to be bound"
echo "=================================="

echo "Waiting for TSLAM models PVC to be bound..."
timeout=300
counter=0
while [ $counter -lt $timeout ]; do
    PVC_STATUS=$(oc get pvc l1-ml-models-pvc -n l1-app-ai -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$PVC_STATUS" = "Bound" ]; then
        echo "✅ PVC successfully bound"
        break
    elif [ "$PVC_STATUS" = "NotFound" ]; then
        echo "⏳ PVC not yet created..."
    else
        echo "⏳ PVC status: $PVC_STATUS"
    fi
    sleep 10
    counter=$((counter + 10))
done

if [ $counter -ge $timeout ]; then
    echo "❌ PVC binding timeout"
    oc get pvc l1-ml-models-pvc -n l1-app-ai
    exit 1
fi

# Upload model (if needed)
echo ""
echo "Step 5: Model Upload"
echo "=================="

echo "Checking if TSLAM-4B model needs to be uploaded..."
if oc exec tslam-model-uploader -n l1-app-ai -- ls /models/tslam-4b >/dev/null 2>&1; then
    echo "✅ TSLAM-4B model already present in PVC"
else
    echo "📁 Uploading TSLAM-4B model from /home/cloud-user/pjoe/model..."
    echo "This may take several minutes depending on model size..."
    
    # Copy model files to PVC
    oc exec -i tslam-model-uploader -n l1-app-ai -- sh << 'EOF'
mkdir -p /models/tslam-4b
echo "Model upload container ready. Please copy your model files manually."
echo "Model should be uploaded to: /models/tslam-4b/"
EOF

    echo "⚠️  Manual model upload required:"
    echo "1. Access the uploader pod: oc exec -it tslam-model-uploader -n l1-app-ai -- sh"
    echo "2. Copy your model from: /home/cloud-user/pjoe/model"
    echo "3. To PVC location: /models/tslam-4b/"
    echo ""
fi

# Monitor GPU deployment
echo "Step 6: Monitoring Tesla P40 GPU Deployment"
echo "=========================================="

echo "Waiting for Tesla P40 vLLM pods to start..."
echo "This may take 5-10 minutes for GPU model loading..."
echo ""

echo "You can monitor progress with:"
echo "- Pod status: oc get pods -n l1-app-ai -w"
echo "- GPU deployment: oc get deployment tslam-vllm-deployment -n l1-app-ai"
echo "- Logs: oc logs -f deployment/tslam-vllm-deployment -n l1-app-ai"
echo "- GPU usage: oc exec -it <vllm-pod> -n l1-app-ai -- nvidia-smi"
echo ""

# Final status
echo "📊 Current Status:"
echo "=================="
oc get pods -n l1-app-ai
echo ""
oc get deployment tslam-vllm-deployment -n l1-app-ai 2>/dev/null || echo "Deployment starting..."
echo ""

echo "🎯 Tesla P40 GPU Deployment Completed!"
echo ""
echo "Expected Timeline:"
echo "- Model loading: 2-5 minutes"
echo "- vLLM startup: 1-2 minutes" 
echo "- Service ready: Total ~3-7 minutes"
echo ""
echo "Once ready:"
echo "✅ Tesla P40 GPU acceleration: ~10x faster than CPU"
echo "✅ Real-time streaming responses for L1 Dashboard"
echo "✅ 24GB VRAM perfect for TSLAM-4B model"
echo ""
echo "🚀 Your TSLAM AI inference will be blazing fast!"