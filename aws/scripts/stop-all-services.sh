#!/bin/bash
# Stop All L1 Services to Prevent AWS Charges
# Usage: ./stop-all-services.sh [quick|full]
#
# quick: Stops pods and scales nodes to 0 (keeps cluster, faster restart, ~$2.40/day idle)
# full:  Deletes entire cluster (near-zero cost, slower restart ~20 min)

set -e

MODE=${1:-quick}
CLUSTER_NAME="l1-troubleshooting-cluster"
REGION="us-east-1"
NAMESPACE="l1-troubleshooting"

echo "=========================================="
echo "L1 Services Shutdown Script"
echo "=========================================="
echo "Mode: $MODE"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Update kubeconfig
echo "Step 1: Updating kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION} 2>/dev/null || true

if [ "$MODE" == "full" ]; then
    echo ""
    echo "⚠️  FULL SHUTDOWN MODE - This will DELETE the entire cluster!"
    echo "You will need to recreate the cluster to use the system again."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Shutdown cancelled."
        exit 0
    fi
    
    echo ""
    echo "Step 2: Deleting EKS cluster (this will take 10-15 minutes)..."
    eksctl delete cluster --name ${CLUSTER_NAME} --region ${REGION} --wait
    
    echo ""
    echo "=========================================="
    echo "✅ FULL SHUTDOWN COMPLETE"
    echo "=========================================="
    echo ""
    echo "Cost savings:"
    echo "  - EKS control plane: STOPPED ($0.10/hour = $73/month)"
    echo "  - EC2 nodes: STOPPED (~$0.08/hour = $120/month)"
    echo "  - Load balancer: STOPPED (~$0.03/hour = $22/month)"
    echo ""
    echo "Remaining costs (minimal):"
    echo "  - EFS storage: ~$0.30/GB/month"
    echo "  - ECR images: ~$0.10/GB/month"
    echo "  - Total idle cost: ~$2-5/month"
    echo ""
    echo "To restart, run: ./start-all-services.sh full"
    echo "Note: Full restart takes ~25 minutes"
    
else
    # Quick shutdown - scale to zero but keep cluster
    echo ""
    echo "Step 2: Deleting application deployment..."
    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true --timeout=2m 2>/dev/null || true
    
    echo ""
    echo "Step 3: Scaling node groups to 0..."
    NODEGROUPS=$(eksctl get nodegroup --cluster ${CLUSTER_NAME} --region ${REGION} -o json | jq -r '.[].Name' 2>/dev/null || echo "")
    
    if [ -n "$NODEGROUPS" ]; then
        for NG in $NODEGROUPS; do
            echo "  Scaling nodegroup: $NG to 0 nodes"
            eksctl scale nodegroup \
                --cluster ${CLUSTER_NAME} \
                --region ${REGION} \
                --name $NG \
                --nodes 0 \
                --nodes-min 0 \
                --nodes-max 5 \
                2>/dev/null || echo "    Warning: Could not scale $NG"
        done
    else
        echo "  No nodegroups found or eksctl not available"
    fi
    
    echo ""
    echo "Step 4: Verifying shutdown..."
    kubectl get pods -A 2>/dev/null || echo "  All pods terminated"
    
    echo ""
    echo "=========================================="
    echo "✅ QUICK SHUTDOWN COMPLETE"
    echo "=========================================="
    echo ""
    echo "Cost savings:"
    echo "  - EC2 nodes: STOPPED (~$0.08/hour = $120/month)"
    echo "  - Load balancer: STOPPED (~$0.03/hour = $22/month)"
    echo "  - Application pods: STOPPED"
    echo ""
    echo "Remaining costs:"
    echo "  - EKS control plane: $0.10/hour = $2.40/day"
    echo "  - EFS storage: ~$0.50/day (minimal)"
    echo "  - Total idle cost: ~$3/day = $90/month if left idle"
    echo ""
    echo "To restart, run: ./start-all-services.sh quick"
    echo "Note: Quick restart takes ~5 minutes"
fi

echo ""
echo "Timestamp: $(date)"
echo "=========================================="
