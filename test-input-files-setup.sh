#!/bin/bash

# Test Input Files PVC Setup
echo "Testing input files PVC setup..."

# Apply the updated pod configuration
kubectl apply -f k8s-pod-production.yaml

# Wait for pod to be ready
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/l1-prod-app -n l1-app-ai --timeout=300s

# Verify volume mounts
echo "Verifying volume mounts..."
kubectl exec -it l1-prod-app -n l1-app-ai -- bash -c "
echo 'Checking mounted directories:'
ls -la /app/
echo
echo 'ML Models directory:'
ls -la /app/models/ 2>/dev/null || echo 'Directory is empty (expected for new deployment)'
echo
echo 'Input Files directory:'
ls -la /app/input_files/ 2>/dev/null || echo 'Directory is empty (expected for new deployment)'
echo
echo 'Volume mounts verified!'
"

# Test folder_anomaly_analyzer_clickhouse.py with default path
echo "Testing folder analyzer with default path..."
kubectl exec -it l1-prod-app -n l1-app-ai -- python3 folder_anomaly_analyzer_clickhouse.py

echo "Test complete!"
echo "TIP: To upload input files:"
echo "   kubectl cp your-file.pcap l1-prod-app:/app/input_files/ -n l1-app-ai"