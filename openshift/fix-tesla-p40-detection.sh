#!/bin/bash

# Fix Tesla P40 GPU Detection - NFD Labels
echo "🔧 Fixing Tesla P40 GPU Detection"
echo "================================"
echo "Issue: NFD labels missing for Tesla P40 GPUs"
echo ""

# Step 1: Check NFD workers
echo "Step 1: Checking NFD Workers"
echo "=========================="
echo "NFD worker pods:"
oc get pods -n openshift-nfd

echo ""
echo "Step 2: Restart NFD Workers (Force Re-scan)"
echo "=========================================="
echo "Restarting NFD workers to re-scan for Tesla P40s..."
oc delete pod -n openshift-nfd -l app=nfd-worker

echo "Waiting for NFD workers to restart..."
sleep 30

echo "New NFD worker pods:"
oc get pods -n openshift-nfd

echo ""
echo "Step 3: Wait and Check Tesla P40 Detection"
echo "========================================"
echo "Waiting 60 seconds for NFD to scan GPUs..."
sleep 60

echo "Checking for NVIDIA PCI labels..."
LABELED_NODES=$(oc get nodes -l feature.node.kubernetes.io/pci-10de.present --no-headers 2>/dev/null | wc -l)

if [ "$LABELED_NODES" -gt 0 ]; then
    echo "✅ Tesla P40 GPUs detected!"
    oc get nodes -l feature.node.kubernetes.io/pci-10de.present
else
    echo "⚠️  NFD still not detecting Tesla P40s. Applying manual labels..."
    
    echo ""
    echo "Step 4: Manual Tesla P40 Labels"
    echo "=============================="
    echo "Manually labeling Tesla P40 GPU nodes..."
    
    # Label your specific GPU nodes
    oc label node rhocp-gx5wg-worker-0-vfm8l feature.node.kubernetes.io/pci-10de.present=true --overwrite
    oc label node rhocp-gx5wg-worker-0-pdg59 feature.node.kubernetes.io/pci-10de.present=true --overwrite
    oc label node rhocp-gx5wg-worker-0-cbmkw feature.node.kubernetes.io/pci-10de.present=true --overwrite
    
    echo "✅ Manual labels applied!"
fi

echo ""
echo "Step 5: Verify GPU Detection"
echo "=========================="
echo "Checking Tesla P40 GPU capacity on nodes..."
oc get nodes -o=custom-columns='Node:metadata.name,GPUs:status.capacity.nvidia\.com/gpu'

echo ""
echo "Waiting 2 minutes for GPU operator to detect Tesla P40s..."
sleep 120

echo "Final Tesla P40 GPU check:"
oc get nodes -o=custom-columns='Node:metadata.name,GPUs:status.capacity.nvidia\.com/gpu'

echo ""
echo "🚀 Tesla P40 Detection Fix Complete!"
echo ""
echo "If GPUs show '1' above, your Tesla P40s are ready!"
echo "Next: Run ./deploy-tslam-gpu-p40.sh"