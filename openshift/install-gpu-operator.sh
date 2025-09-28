#!/bin/bash

# OpenShift Tesla P40 GPU Operator Installation Script
# This script enables Tesla P40 GPUs for vLLM inference

set -e

echo "🚀 OpenShift Tesla P40 GPU Operator Installation"
echo "================================================"
echo "This script will:"
echo "1. Install Node Feature Discovery (NFD) Operator"
echo "2. Install NVIDIA GPU Operator" 
echo "3. Create ClusterPolicy for Tesla P40s"
echo "4. Verify Tesla P40 GPU accessibility"
echo ""

# Step 1: Install Node Feature Discovery (NFD)
echo "Step 1: Installing Node Feature Discovery (NFD) Operator"
echo "======================================================="

echo "Creating NFD namespace..."
oc create -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-nfd
EOF

echo "Creating NFD OperatorGroup..."
oc create -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nfd-operator-group
  namespace: openshift-nfd
spec:
  targetNamespaces:
  - openshift-nfd
EOF

echo "Installing NFD Subscription..."
oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: "stable"
  installPlanApproval: Automatic
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "✅ NFD Operator installation initiated"
echo ""

# Wait for NFD to be ready
echo "Waiting for NFD operator to be ready..."
sleep 30

# Step 2: Install NVIDIA GPU Operator
echo "Step 2: Installing NVIDIA GPU Operator"
echo "======================================"

echo "Creating GPU operator namespace..."
oc create -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: nvidia-gpu-operator
EOF

echo "Creating GPU OperatorGroup..."
oc create -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator-group
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
  - nvidia-gpu-operator
EOF

echo "Installing GPU Operator Subscription..."
oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: "stable"
  installPlanApproval: Automatic
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF

echo "✅ GPU Operator installation initiated"
echo ""

# Wait for GPU operator to be ready
echo "Waiting for GPU operator to be ready..."
sleep 60

# Step 3: Create ClusterPolicy
echo "Step 3: Creating ClusterPolicy for Tesla P40 GPUs"
echo "==============================================="

echo "Creating ClusterPolicy..."
oc create -f - <<EOF
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
  dcgm:
    enabled: true
  driver:
    enabled: true
  toolkit:
    enabled: true
  devicePlugin:
    enabled: true
  nodeFeatureDiscovery:
    enabled: true
EOF

echo "✅ ClusterPolicy created"
echo ""

# Step 4: Verification
echo "Step 4: Verifying Installation"
echo "============================="

echo "Waiting for installation to complete (this may take 10-15 minutes)..."
echo "You can monitor progress with: oc get pods -n nvidia-gpu-operator -w"
echo ""

# Function to check installation status
check_status() {
    echo "Checking operator installations..."
    echo ""
    
    echo "NFD Operator status:"
    oc get csv -n openshift-nfd 2>/dev/null || echo "NFD not yet ready"
    echo ""
    
    echo "GPU Operator status:"
    oc get csv -n nvidia-gpu-operator 2>/dev/null || echo "GPU Operator not yet ready"
    echo ""
    
    echo "ClusterPolicy status:"
    oc get clusterpolicy 2>/dev/null || echo "ClusterPolicy not yet ready"
    echo ""
    
    echo "GPU Operator pods:"
    oc get pods -n nvidia-gpu-operator 2>/dev/null || echo "GPU pods not yet created"
    echo ""
}

# Initial status check
check_status

echo "🎯 Installation Commands Completed!"
echo ""
echo "Next Steps:"
echo "1. Wait 10-15 minutes for full installation"
echo "2. Verify with: oc get clusterpolicy"
echo "3. Should see 'State: ready' when complete"
echo "4. Check Tesla P40s: oc get nodes -o yaml | grep nvidia.com/gpu"
echo "5. Once ready, we can deploy GPU-accelerated vLLM!"
echo ""
echo "Monitor installation: oc get pods -n nvidia-gpu-operator -w"
echo ""
echo "🚀 Your Tesla P40s will be ready for TSLAM inference soon!"