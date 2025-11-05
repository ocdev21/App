#!/bin/bash
# Upload AI model to EFS volume via temporary pod
# Usage: ./upload-model-to-efs.sh <PATH_TO_MODEL_FILE>

set -e

MODEL_FILE=${1:-"mistral-7b-instruct-v0.2.Q4_K_M.gguf"}
NAMESPACE="l1-troubleshooting"

if [ ! -f "$MODEL_FILE" ]; then
    echo "Error: Model file not found: $MODEL_FILE"
    exit 1
fi

echo "=========================================="
echo "Uploading AI Model to EFS"
echo "=========================================="
echo "Model file: $MODEL_FILE"
echo "Namespace: $NAMESPACE"
echo "=========================================="

# Create temporary pod to mount EFS
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: efs-upload-pod
  namespace: ${NAMESPACE}
spec:
  containers:
  - name: alpine
    image: alpine:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: models
      mountPath: /models
  volumes:
  - name: models
    persistentVolumeClaim:
      claimName: l1-models-pvc
EOF

# Wait for pod to be ready
echo "Waiting for upload pod to be ready..."
kubectl wait --for=condition=ready pod/efs-upload-pod -n ${NAMESPACE} --timeout=120s

# Copy model file to EFS
echo "Uploading model file to EFS..."
kubectl cp "$MODEL_FILE" ${NAMESPACE}/efs-upload-pod:/models/mistral.gguf

echo "Verifying upload..."
kubectl exec -n ${NAMESPACE} efs-upload-pod -- ls -lh /models/

# Cleanup
echo "Cleaning up upload pod..."
kubectl delete pod efs-upload-pod -n ${NAMESPACE}

echo "=========================================="
echo "✅ Model uploaded successfully to EFS!"
echo "=========================================="
