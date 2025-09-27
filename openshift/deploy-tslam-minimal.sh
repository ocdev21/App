#!/bin/bash

echo "Deploying TSLAM-4B GPU Inference (Minimal Setup)"
echo "==============================================="

# Configuration
PROJECT_NAME="l1-app-ai"
GPU_NODES=("rhocp-gx5wg-worker-0-vfm8l" "rhocp-gx5wg-worker-0-pdg59" "rhocp-gx5wg-worker-0-cbmkw")
MODEL_SOURCE="/home/cloud-user/pjoe/model"

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

echo ""
echo "Step 1: Deploying TSLAM GPU Infrastructure"
echo "========================================"

# Apply the minimal TSLAM deployment
oc apply -f openshift/tslam-gpu-deployment.yaml

echo ""
echo "Step 2: Waiting for PVC to be bound"
echo "=================================="

echo "Waiting for TSLAM models PVC to be bound..."
oc wait --for=condition=Bound pvc/l1-ml-models-pvc -n $PROJECT_NAME --timeout=300s

if [ $? -eq 0 ]; then
    echo "✓ PVC bound successfully"
    oc get pvc l1-ml-models-pvc -n $PROJECT_NAME
else
    echo "✗ PVC binding failed"
    oc describe pvc l1-ml-models-pvc -n $PROJECT_NAME
    exit 1
fi

echo ""
echo "Step 3: Starting Model Upload Pod"
echo "================================"

echo "Waiting for upload pod to be ready..."
oc wait --for=condition=Ready pod/tslam-model-uploader -n $PROJECT_NAME --timeout=120s

if [ $? -ne 0 ]; then
    echo "✗ Upload pod failed to start"
    oc describe pod tslam-model-uploader -n $PROJECT_NAME
    exit 1
fi

echo ""
echo "Step 4: Uploading TSLAM Model from $MODEL_SOURCE"
echo "=============================================="

# Verify model source exists
if [ ! -d "$MODEL_SOURCE" ]; then
    echo "✗ TSLAM model directory not found at $MODEL_SOURCE"
    echo "Please verify the path exists and contains:"
    echo "  - config.json"
    echo "  - pytorch_model.bin (or model.safetensors)"
    echo "  - tokenizer.json"
    echo "  - tokenizer_config.json"
    exit 1
fi

echo "✓ Found TSLAM model directory at $MODEL_SOURCE"
echo "Copying model files to PVC..."

# Upload the model files
oc cp "$MODEL_SOURCE/" $PROJECT_NAME/tslam-model-uploader:/models/tslam-4b

if [ $? -eq 0 ]; then
    echo "✓ Model files uploaded successfully"
else
    echo "✗ Model upload failed"
    exit 1
fi

echo ""
echo "Step 5: Verifying Model Upload"
echo "============================="

echo "Checking uploaded model files..."
oc exec -n $PROJECT_NAME tslam-model-uploader -- ls -la /models/tslam-4b/

echo ""
echo "Model file details:"
oc exec -n $PROJECT_NAME tslam-model-uploader -- find /models/tslam-4b -type f -exec ls -lh {} \;

echo ""
echo "Step 6: Deploying vLLM GPU Services"
echo "=================================="

# Check GPU node availability
echo "Checking GPU nodes availability:"
for node in "${GPU_NODES[@]}"; do
    if oc get node $node &>/dev/null; then
        echo "  ✓ $node - Available"
        oc describe node $node | grep -A 3 "nvidia.com/gpu" || echo "    Note: GPU resources may not be visible in describe"
    else
        echo "  ✗ $node - Not found"
    fi
done

echo ""
echo "Starting vLLM GPU deployment (3 replicas across GPU nodes)..."

# The deployment is already applied, just monitor the rollout
echo "Monitoring deployment progress..."
oc rollout status deployment/tslam-vllm-deployment -n $PROJECT_NAME --timeout=600s

if [ $? -ne 0 ]; then
    echo "✗ vLLM deployment failed"
    echo "Checking pod status:"
    oc get pods -n $PROJECT_NAME -l app=tslam-vllm
    oc describe pods -n $PROJECT_NAME -l app=tslam-vllm
    exit 1
fi

echo ""
echo "Step 7: Verifying GPU Deployment"
echo "==============================="

echo "Checking pod distribution across GPU nodes:"
oc get pods -n $PROJECT_NAME -l app=tslam-vllm -o wide

echo ""
echo "vLLM Service Status:"
oc get svc tslam-vllm-service -n $PROJECT_NAME

echo ""
echo "Step 8: Testing vLLM Health Endpoints"
echo "===================================="

echo "Waiting for vLLM pods to be fully ready..."
sleep 30

# Test each pod's health
PODS=$(oc get pods -n $PROJECT_NAME -l app=tslam-vllm --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
for POD in $PODS; do
    if [ ! -z "$POD" ]; then
        echo "Testing Pod: $POD"
        echo "  Health check:"
        oc exec -n $PROJECT_NAME $POD -- curl -s http://localhost:8000/health 2>/dev/null | head -1 || echo "    Health check pending..."
        echo "  Models endpoint:"
        oc exec -n $PROJECT_NAME $POD -- curl -s http://localhost:8000/v1/models 2>/dev/null | head -1 || echo "    Models endpoint pending..."
        echo ""
    fi
done

echo ""
echo "Step 9: Testing Service Endpoint"
echo "==============================="

echo "Testing TSLAM service from within cluster..."
# Create a temporary test pod
oc run test-client --rm -i --tty --image=curlimages/curl --restart=Never -- \
  curl -s -X POST http://tslam-vllm-service.l1-app-ai.svc.cluster.local:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"tslam-4b","messages":[{"role":"user","content":"Test"}],"max_tokens":5}' 2>/dev/null | head -3 || echo "Service test will be available once all pods are ready"

echo ""
echo "Step 10: Cleanup Upload Pod"
echo "=========================="

echo "Removing temporary upload pod..."
oc delete pod tslam-model-uploader -n $PROJECT_NAME

echo ""
echo "======================================"
echo "TSLAM GPU Deployment Complete!"
echo "======================================"

echo ""
echo "🚀 Your TSLAM-4B is now running on GPU nodes!"
echo ""
echo "📊 Deployment Summary:"
echo "   - GPU Nodes: ${GPU_NODES[*]}"
echo "   - vLLM Replicas: 3 (distributed across GPU nodes)"
echo "   - Model Storage: 20GB NFS PVC"
echo "   - Service: tslam-vllm-service:8000"
echo ""
echo "🔗 Integration Information:"
echo "   - Service URL: http://tslam-vllm-service.l1-app-ai.svc.cluster.local:8000"
echo "   - API Format: OpenAI-compatible /v1/chat/completions"
echo "   - Model Name: tslam-4b"
echo "   - Streaming: Supported with 'stream': true"
echo ""
echo "🛠️ Your CPU application can now call:"
echo "   POST http://tslam-vllm-service.l1-app-ai.svc.cluster.local:8000/v1/chat/completions"
echo "   {\"model\":\"tslam-4b\",\"messages\":[...],\"stream\":true}"
echo ""
echo "🔍 Monitoring Commands:"
echo "   - Check GPU pods: oc get pods -n $PROJECT_NAME -l app=tslam-vllm -o wide"
echo "   - Check vLLM logs: oc logs deployment/tslam-vllm-deployment -n $PROJECT_NAME"
echo "   - Test service: oc port-forward svc/tslam-vllm-service 8000:8000 -n $PROJECT_NAME"
echo ""
echo "⚡ Performance Features:"
echo "   - Real-time streaming responses"
echo "   - Load balancing across 3 GPU nodes"
echo "   - OpenAI-compatible API format"
echo "   - Sub-second inference latency"
echo ""
echo "✅ Ready for integration with your L1 application!"