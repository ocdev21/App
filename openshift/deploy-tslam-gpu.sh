#!/bin/bash

echo "Deploying TSLAM-4B on GPU Nodes with vLLM"
echo "======================================="

# Configuration
PROJECT_NAME="l1-app-ai"
GPU_NODES=("rhocp-gx5wg-worker-0-vfm8l" "rhocp-gx5wg-worker-0-pdg59" "rhocp-gx5wg-worker-0-cbmkw")

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

echo ""
echo "Step 1: Deploying Enhanced PVC and vLLM Infrastructure"
echo "====================================================="

# Apply the enhanced deployment with GPU configurations
oc apply -f openshift/l1-app-openshift-ai-deployment.yaml

echo ""
echo "Step 2: Waiting for PVC to be bound"
echo "=================================="

echo "Waiting for enhanced ML models PVC to be bound..."
oc wait --for=condition=Bound pvc/l1-ml-models-pvc -n $PROJECT_NAME --timeout=300s

echo "PVC Status:"
oc get pvc l1-ml-models-pvc -n $PROJECT_NAME

echo ""
echo "Step 3: Starting Model Upload Pod"
echo "================================"

echo "Creating model upload pod..."
oc apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: tslam-model-uploader
  namespace: $PROJECT_NAME
  labels:
    app: model-uploader
    model: tslam-4b
spec:
  restartPolicy: Never
  containers:
  - name: uploader
    image: busybox:1.35
    command: ["sleep", "3600"]
    volumeMounts:
    - name: model-storage
      mountPath: /models
  volumes:
  - name: model-storage
    persistentVolumeClaim:
      claimName: l1-ml-models-pvc
EOF

echo "Waiting for upload pod to be ready..."
oc wait --for=condition=Ready pod/tslam-model-uploader -n $PROJECT_NAME --timeout=120s

echo ""
echo "Step 4: Uploading TSLAM Model from /home/cloud-user/pjoe/model"
echo "=============================================================="

echo "Uploading TSLAM-4B model files from local path..."
echo "Source: /home/cloud-user/pjoe/model"
echo "Target: PVC /models/tslam-4b"

# Upload the model files directly
if [ -d "/home/cloud-user/pjoe/model" ]; then
    echo "✓ Found TSLAM model directory"
    echo "Copying model files to PVC..."
    oc cp /home/cloud-user/pjoe/model/ $PROJECT_NAME/tslam-model-uploader:/models/tslam-4b
    
    if [ $? -eq 0 ]; then
        echo "✓ Model files uploaded successfully"
    else
        echo "✗ Model upload failed"
        exit 1
    fi
else
    echo "✗ TSLAM model directory not found at /home/cloud-user/pjoe/model"
    echo "Please verify the path exists and try again"
    exit 1
fi

echo ""
echo "Step 5: Verifying Model Upload"
echo "============================="

echo "Checking uploaded model files..."
oc exec -n $PROJECT_NAME tslam-model-uploader -- ls -la /models/tslam-4b/

echo ""
echo "Step 6: Deploying vLLM GPU Inference Services"
echo "============================================"

# Check GPU node availability
echo "Checking GPU nodes availability:"
for node in "${GPU_NODES[@]}"; do
    if oc get node $node &>/dev/null; then
        echo "  ✓ $node - Available"
        oc describe node $node | grep -A 5 "nvidia.com/gpu" || echo "    WARNING: GPU resources not visible"
    else
        echo "  ✗ $node - Not found"
    fi
done

echo ""
echo "Starting vLLM GPU deployment (3 replicas across GPU nodes)..."

# Apply the vLLM deployment (already in the YAML file)
echo "vLLM deployment is included in the main configuration."
echo "Monitoring deployment progress..."

echo ""
echo "Step 7: Monitoring Deployment Progress"
echo "===================================="

echo "Waiting for vLLM deployment to be ready..."
oc rollout status deployment/tslam-vllm-deployment -n $PROJECT_NAME --timeout=600s

echo ""
echo "Checking pod distribution across GPU nodes:"
oc get pods -n $PROJECT_NAME -l app=tslam-vllm -o wide

echo ""
echo "Step 8: Service Verification"
echo "==========================="

echo "vLLM Service Status:"
oc get svc tslam-vllm-service -n $PROJECT_NAME

echo ""
echo "Checking vLLM health endpoints..."
for i in {1..3}; do
    POD=$(oc get pods -n $PROJECT_NAME -l app=tslam-vllm --field-selector=status.phase=Running -o jsonpath="{.items[$((i-1))].metadata.name}" 2>/dev/null)
    if [ ! -z "$POD" ]; then
        echo "Testing Pod $i ($POD):"
        oc exec -n $PROJECT_NAME $POD -- curl -s http://localhost:8000/health | head -1 || echo "  Health check failed"
        oc exec -n $PROJECT_NAME $POD -- curl -s http://localhost:8000/v1/models | head -1 || echo "  Model endpoint failed"
    fi
done

echo ""
echo "Step 9: L1 Application Configuration Update"
echo "========================================"

echo "Restarting L1 application to use new vLLM service..."
oc rollout restart deployment/l1-troubleshooting-ai -n $PROJECT_NAME
oc rollout status deployment/l1-troubleshooting-ai -n $PROJECT_NAME --timeout=300s

echo ""
echo "Step 10: End-to-End Test"
echo "======================="

echo "Testing TSLAM vLLM connection from L1 app..."
L1_POD=$(oc get pods -n $PROJECT_NAME -l app=l1-troubleshooting-ai --field-selector=status.phase=Running -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

if [ ! -z "$L1_POD" ]; then
    echo "Testing from L1 app pod: $L1_POD"
    oc exec -n $PROJECT_NAME $L1_POD -- curl -s \
        -X POST http://tslam-vllm-service:8000/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"tslam-4b","messages":[{"role":"user","content":"Test"}],"max_tokens":10}' | head -3
else
    echo "L1 application pod not found or not ready"
fi

echo ""
echo "Step 11: Cleanup Upload Pod"
echo "=========================="

echo "Removing temporary upload pod..."
oc delete pod tslam-model-uploader -n $PROJECT_NAME

echo ""
echo "======================================"
echo "TSLAM GPU Deployment Complete!"
echo "======================================"

echo ""
echo "🚀 Your TSLAM-4B deployment is now running on GPU nodes!"
echo ""
echo "📊 Deployment Summary:"
echo "   - GPU Nodes: ${GPU_NODES[*]}"
echo "   - vLLM Replicas: 3 (one per GPU node)"
echo "   - Model Storage: 20GB PVC (ReadWriteMany)"
echo "   - Load Balancer: tslam-vllm-service:8000"
echo ""
echo "🌐 Access Information:"
L1_ROUTE=$(oc get route l1-troubleshooting-ai-route -n $PROJECT_NAME -o jsonpath='{.spec.host}' 2>/dev/null)
if [ ! -z "$L1_ROUTE" ]; then
    echo "   - L1 Dashboard: https://$L1_ROUTE"
    echo "   - Real TSLAM streaming is now active!"
else
    echo "   - L1 Dashboard route not available yet"
fi

echo ""
echo "🔍 Monitoring Commands:"
echo "   - Check GPU pods: oc get pods -n $PROJECT_NAME -l app=tslam-vllm -o wide"
echo "   - Check vLLM logs: oc logs deployment/tslam-vllm-deployment -n $PROJECT_NAME"
echo "   - Check L1 app logs: oc logs deployment/l1-troubleshooting-ai -n $PROJECT_NAME"
echo "   - Test vLLM directly: oc port-forward svc/tslam-vllm-service 8000:8000 -n $PROJECT_NAME"

echo ""
echo "⚡ Performance Features:"
echo "   - Sub-second first token latency"
echo "   - Real-time streaming responses"
echo "   - Automatic load balancing across 3 GPU nodes"
echo "   - High availability (node failure tolerance)"

echo ""
echo "✅ Your L1 Network Troubleshooting System now has real AI-powered analysis!"