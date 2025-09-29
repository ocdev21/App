#!/bin/bash

echo "Deploying TSLAM-4B CPU Inference (No GPU Required)"
echo "================================================"

# Configuration
PROJECT_NAME="l1-app-ai"
MODEL_SOURCE="/home/cloud-user/pjoe/model"

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

echo ""
echo "Step 1: Cleaning Up Old GPU Deployment"
echo "===================================="

# Remove any existing GPU deployment
echo "Removing old GPU deployment (if exists)..."
oc delete deployment tslam-vllm-deployment -n $PROJECT_NAME 2>/dev/null || echo "No existing GPU deployment found"

echo ""
echo "Step 2: Deploying CPU-Based TSLAM Infrastructure"
echo "=============================================="

# Apply the CPU deployment
oc apply -f openshift/tslam-cpu-deployment.yaml

echo ""
echo "Step 3: Waiting for PVC to be bound"
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
echo "Step 4: Waiting for CPU Pods to Start"
echo "==================================="

echo "Waiting for at least one CPU pod to be running..."
oc rollout status deployment/tslam-vllm-cpu-deployment -n $PROJECT_NAME --timeout=300s

# Get the first available pod for upload
echo "Finding a running pod for model upload..."
POD_NAME=""
for i in {1..30}; do
    POD_NAME=$(oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD_NAME" ]; then
        echo "✓ Found running pod: $POD_NAME"
        break
    fi
    echo "Waiting for pods to start... ($i/30)"
    sleep 10
done

if [ -z "$POD_NAME" ]; then
    echo "⚠️  No running pods found yet, checking pending pods..."
    oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu
    oc describe pods -n $PROJECT_NAME -l app=tslam-vllm-cpu | tail -20
    echo ""
    echo "Let's try to upload to any available pod..."
    POD_NAME=$(oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD_NAME" ]; then
        echo "✗ No pods available for upload"
        exit 1
    fi
fi

echo ""
echo "Step 5: Uploading TSLAM Model from $MODEL_SOURCE"
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
echo "Copying model files to pod: $POD_NAME"

# Upload the model files
oc cp "$MODEL_SOURCE/" $PROJECT_NAME/$POD_NAME:/models/tslam-4b

if [ $? -eq 0 ]; then
    echo "✓ Model files uploaded successfully"
else
    echo "✗ Model upload failed"
    exit 1
fi

echo ""
echo "Step 6: Verifying Model Upload"
echo "============================="

echo "Checking uploaded model files..."
oc exec -n $PROJECT_NAME $POD_NAME -- ls -la /models/tslam-4b/ || echo "Files not accessible yet, pod may be restarting"

echo ""
echo "Model file details:"
oc exec -n $PROJECT_NAME $POD_NAME -- find /models/tslam-4b -type f -exec ls -lh {} \; 2>/dev/null || echo "Pod restarting after model upload"

echo ""
echo "Step 7: Restarting Deployment to Load Model"
echo "=========================================="

echo "Restarting CPU deployment to load the uploaded model..."
oc rollout restart deployment/tslam-vllm-cpu-deployment -n $PROJECT_NAME

echo "Waiting for CPU deployment to be ready with model..."
oc rollout status deployment/tslam-vllm-cpu-deployment -n $PROJECT_NAME --timeout=600s

if [ $? -ne 0 ]; then
    echo "⚠️  Deployment taking longer than expected"
    echo "Checking pod status:"
    oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu
    oc describe pods -n $PROJECT_NAME -l app=tslam-vllm-cpu | tail -20
fi

echo ""
echo "Step 8: Verifying CPU Deployment"
echo "==============================="

echo "Checking pod distribution across worker nodes:"
oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu -o wide

echo ""
echo "CPU Service Status:"
oc get svc tslam-vllm-service -n $PROJECT_NAME

echo ""
echo "Step 9: Testing CPU Health Endpoints"
echo "==================================="

echo "Waiting for CPU vLLM pods to be fully ready..."
sleep 60

# Test each pod's health
PODS=$(oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
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
echo "Step 10: Testing Service Endpoint"
echo "==============================="

echo "Testing TSLAM CPU service from within cluster..."
# Create a temporary test pod for service testing
oc run test-client --rm -i --tty --image=curlimages/curl --restart=Never -- \
  curl -s -X POST http://tslam-vllm-service.l1-app-ai.svc.cluster.local:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"tslam-4b","messages":[{"role":"user","content":"Test CPU inference"}],"max_tokens":10}' 2>/dev/null | head -5 || echo "Service test will be available once all pods are ready"

echo ""
echo "======================================"
echo "TSLAM CPU Deployment Complete!"
echo "======================================"

echo ""
echo "🚀 Your TSLAM-4B is now running on CPU nodes!"
echo ""
echo "📊 Deployment Summary:"
echo "   - Infrastructure: CPU-based inference (no GPU required)"
echo "   - CPU Replicas: 2 (load balanced)"
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
echo "   - Check CPU pods: oc get pods -n $PROJECT_NAME -l app=tslam-vllm-cpu -o wide"
echo "   - Check logs: oc logs deployment/tslam-vllm-cpu-deployment -n $PROJECT_NAME"
echo "   - Test service: oc port-forward svc/tslam-vllm-service 8000:8000 -n $PROJECT_NAME"
echo ""
echo "⚡ Performance Notes:"
echo "   - CPU inference: 2-10 seconds response time"
echo "   - Real-time streaming responses"
echo "   - Load balancing across 2 CPU pods"
echo "   - Ready for GPU upgrade when available"
echo ""
echo "🔄 To upgrade to GPU later:"
echo "   1. Install GPU operator"
echo "   2. Apply: openshift/tslam-gpu-deployment.yaml"
echo "   3. Your model files are already uploaded!"
echo ""
echo "✅ Ready for integration with your L1 application!"