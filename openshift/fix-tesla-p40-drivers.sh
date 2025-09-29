#!/bin/bash

# Tesla P40 Driver Fix Script - Address Common Issues
echo "🔧 Tesla P40 Driver Fix Script"
echo "=============================="
echo "This fixes common Tesla P40 detection issues in OpenShift"
echo ""

echo "Step 1: Delete Current ClusterPolicy"
echo "=================================="
echo "Removing current ClusterPolicy to recreate with Tesla P40 settings..."
oc delete clusterpolicy gpu-cluster-policy 2>/dev/null || echo "No existing ClusterPolicy"

echo "Waiting for cleanup..."
sleep 30

echo ""
echo "Step 2: Create Tesla P40 Optimized ClusterPolicy"
echo "=============================================="
echo "Creating ClusterPolicy optimized for Tesla P40 (Pascal architecture)..."

oc apply -f - <<EOF
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
    use_ocp_driver_toolkit: false  # Disable for compatibility
  driver:
    enabled: true
    version: "470.199.02"  # Tesla-compatible driver version
    repository: "nvcr.io/nvidia"
    use_ocp_driver_toolkit: false  # Force standard drivers
  toolkit:
    enabled: true
    version: "1.14.3-ubuntu20.04"
  devicePlugin:
    enabled: true
    config:
      name: ""
      default: ""
  dcgm:
    enabled: true
  dcgmExporter:
    enabled: true
  nodeStatusExporter:
    enabled: true
  gfd:
    enabled: true
  migManager:
    enabled: false  # Tesla P40 doesn't support MIG
  validator:
    plugin:
      env:
      - name: WITH_WORKLOAD
        value: "false"  # Disable workload validation for Tesla
  vfioManager:
    enabled: false
  sandboxWorkloads:
    enabled: false
    defaultWorkload: "container"
  cdi:
    enabled: false
    default: false
EOF

echo "✅ Tesla P40 optimized ClusterPolicy created!"

echo ""
echo "Step 3: Wait for Driver Installation"
echo "=================================="
echo "Waiting for Tesla P40 drivers to install (this takes 10-15 minutes)..."
echo "Monitor with: oc get pods -n nvidia-gpu-operator -w"

# Monitor ClusterPolicy status
echo ""
echo "Checking ClusterPolicy status every 60 seconds..."
for i in {1..20}; do
    sleep 60
    STATE=$(oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "creating")
    echo "[$i/20] ClusterPolicy state: $STATE"
    
    if [ "$STATE" = "ready" ]; then
        echo "✅ ClusterPolicy is ready!"
        break
    fi
done

echo ""
echo "Step 4: Verify Tesla P40 Detection"
echo "================================"
echo "Checking Tesla P40 GPU detection..."
oc get nodes -o=custom-columns='Node:metadata.name,GPUs:status.capacity.nvidia\.com/gpu'

echo ""
echo "🎯 Tesla P40 Driver Fix Complete!"
echo ""
echo "If GPUs still show 'None':"
echo "1. Check hardware: oc debug node/<gpu-node> -- chroot /host lspci | grep NVIDIA"
echo "2. Check driver logs: oc logs -l app=nvidia-driver-daemonset -n nvidia-gpu-operator"
echo "3. OpenShift version may need cluster-wide entitlement (< 4.9.9)"
echo ""
echo "Once GPUs detected, run: ./deploy-tslam-gpu-p40.sh"