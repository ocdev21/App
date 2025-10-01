#!/bin/bash

# Deep Tesla P40 Diagnostic Script
echo "🔬 Deep Tesla P40 Diagnostic - Finding Root Cause"
echo "=================================================="
echo ""

# Step 1: Hardware Level Detection
echo "Step 1: Hardware Level GPU Detection"
echo "=================================="
echo "Checking if Tesla P40 is visible at hardware level..."

echo "Debugging GPU node: rhocp-gx5wg-worker-0-vfm8l"
oc debug node/rhocp-gx5wg-worker-0-vfm8l -- chroot /host lspci | grep -i nvidia || echo "No NVIDIA GPUs found in lspci"

echo ""
echo "Step 2: Driver Pods Status"
echo "========================"
echo "Checking GPU operator driver pods..."
oc get pods -n nvidia-gpu-operator | grep driver

echo ""
echo "Driver pod logs (checking for errors):"
DRIVER_POD=$(oc get pods -n nvidia-gpu-operator -l app=nvidia-driver-daemonset --no-headers | head -1 | awk '{print $1}')
if [ ! -z "$DRIVER_POD" ]; then
    echo "Checking driver pod: $DRIVER_POD"
    oc logs $DRIVER_POD -n nvidia-gpu-operator --tail=50 | grep -i -E "(error|fail|tesla|p40)"
else
    echo "❌ No driver pods found!"
fi

echo ""
echo "Step 3: OpenShift Version & Driver Toolkit"
echo "========================================"
echo "OpenShift version:"
oc version | grep "Server Version"

echo ""
echo "Driver toolkit availability:"
oc get imagestream driver-toolkit -n openshift 2>/dev/null || echo "❌ Driver toolkit not available"

echo ""
echo "Step 4: ClusterPolicy Detailed Status"
echo "==================================="
echo "Current ClusterPolicy configuration:"
oc get clusterpolicy gpu-cluster-policy -o yaml | grep -A 20 "spec:"

echo ""
echo "Step 5: Node Feature Discovery Status"
echo "==================================="
echo "NFD worker pods:"
oc get pods -n openshift-nfd

echo ""
echo "NFD worker logs (checking Tesla P40 detection):"
NFD_POD=$(oc get pods -n openshift-nfd -l app=nfd-worker --no-headers | head -1 | awk '{print $1}')
if [ ! -z "$NFD_POD" ]; then
    oc logs $NFD_POD -n openshift-nfd --tail=30 | grep -i -E "(pci|nvidia|10de)"
else
    echo "❌ No NFD worker pods found!"
fi

echo ""
echo "Step 6: All GPU Operator Pods Status"
echo "=================================="
oc get pods -n nvidia-gpu-operator -o wide

echo ""
echo "Step 7: Node Labels Check"
echo "======================="
echo "Checking manual labels on GPU nodes:"
oc get node rhocp-gx5wg-worker-0-vfm8l --show-labels | grep -i nvidia
oc get node rhocp-gx5wg-worker-0-pdg59 --show-labels | grep -i nvidia  
oc get node rhocp-gx5wg-worker-0-cbmkw --show-labels | grep -i nvidia

echo ""
echo "🎯 DIAGNOSIS COMPLETE"
echo "===================="
echo ""
echo "Key Things to Check:"
echo "1. Hardware Detection: Did lspci show NVIDIA Tesla P40?"
echo "2. Driver Pods: Are driver pods running? Any errors in logs?"
echo "3. OpenShift Version: Is driver-toolkit available?"
echo "4. NFD Detection: Did NFD detect PCI device 10de (NVIDIA)?"
echo ""
echo "Common Tesla P40 Issues:"
echo "- Driver toolkit not available (OpenShift < 4.9.9)" 
echo "- Wrong driver version selected"
echo "- Tesla P40 hardware not properly seated/powered"
echo "- Nouveau driver conflict"
echo ""
echo "Next steps based on findings above..."