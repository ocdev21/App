#!/bin/bash

# Create ClusterPolicy for Tesla P40 GPUs
echo "🚀 Creating ClusterPolicy for Tesla P40 GPUs"
echo "==========================================="

# Create the ClusterPolicy
echo "Creating ClusterPolicy..."
oc apply -f - <<EOF
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
    use_ocp_driver_toolkit: true
  driver:
    enabled: true
    use_ocp_driver_toolkit: true
  toolkit:
    enabled: true
  devicePlugin:
    enabled: true
  dcgm:
    enabled: true
  dcgmExporter:
    enabled: true
  daemonsets:
    updateStrategy: "RollingUpdate"
    rollingUpdate:
      maxUnavailable: "1"
  gfd:
    enabled: true
  migManager:
    enabled: true
  nodeStatusExporter:
    enabled: true
  validator:
    plugin:
      env:
      - name: WITH_WORKLOAD
        value: "true"
  vfioManager:
    enabled: true
  sandboxWorkloads:
    enabled: false
    defaultWorkload: "container"
  cdi:
    enabled: false
    default: false
EOF

echo "✅ ClusterPolicy created!"
echo ""

echo "📊 Checking status..."
oc get clusterpolicy

echo ""
echo "🔄 Monitor progress with:"
echo "oc get clusterpolicy -w"
echo ""
echo "🎯 When ready, ClusterPolicy will show: State: ready"
echo "🚀 Then your Tesla P40s will be enabled for GPU workloads!"