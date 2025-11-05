#!/bin/bash
# Check Current AWS Costs for L1 Troubleshooting System
# Shows what's running and estimated hourly costs

CLUSTER_NAME="l1-troubleshooting-cluster"
REGION="us-east-1"

echo "=========================================="
echo "L1 System - Current Cost Analysis"
echo "=========================================="
echo "Timestamp: $(date)"
echo ""

# Check if cluster exists
echo "Checking EKS Cluster..."
CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    echo "  ❌ Cluster not found - ZERO COST (except EFS/ECR storage)"
    echo ""
    echo "Estimated idle costs:"
    echo "  - EFS storage: ~$0.50/day"
    echo "  - ECR images: ~$0.10/day"
    echo "  - Total: ~$0.60/day = $18/month"
    exit 0
fi

echo "  ✅ Cluster Status: $CLUSTER_STATUS"
echo "  💰 EKS Control Plane: $0.10/hour = $2.40/day = $73/month"
echo ""

# Check nodes
echo "Checking EC2 Nodes..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION} 2>/dev/null
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

if [ "$NODE_COUNT" -eq 0 ]; then
    echo "  ❌ No nodes running - NODES STOPPED"
    echo "  💰 Node Cost: $0/hour"
else
    echo "  ✅ Nodes Running: $NODE_COUNT"
    echo "  💰 Node Cost (t3.large): ~$0.0832/hour x $NODE_COUNT = $$(echo "$NODE_COUNT * 0.0832" | bc)/hour"
    echo ""
    kubectl get nodes
fi
echo ""

# Check pods
echo "Checking Application Pods..."
POD_COUNT=$(kubectl get pods -n l1-troubleshooting --no-headers 2>/dev/null | wc -l)

if [ "$POD_COUNT" -eq 0 ]; then
    echo "  ❌ No application pods running"
else
    echo "  ✅ Pods Running: $POD_COUNT"
    kubectl get pods -n l1-troubleshooting
fi
echo ""

# Check load balancer
echo "Checking Load Balancer..."
ALB_COUNT=$(kubectl get ingress -n l1-troubleshooting --no-headers 2>/dev/null | wc -l)

if [ "$ALB_COUNT" -eq 0 ]; then
    echo "  ❌ No load balancer provisioned"
    echo "  💰 ALB Cost: $0/hour"
else
    echo "  ✅ ALB Provisioned: $ALB_COUNT"
    echo "  💰 ALB Cost: ~$0.0225/hour = $0.54/day"
    kubectl get ingress -n l1-troubleshooting
fi
echo ""

# Check EFS
echo "Checking EFS Storage..."
EFS_LIST=$(aws efs describe-file-systems --region ${REGION} --query 'FileSystems[?Name==`l1-troubleshooting-efs`]' 2>/dev/null)
EFS_SIZE=$(echo $EFS_LIST | jq -r '.[0].SizeInBytes.Value' 2>/dev/null || echo "0")

if [ "$EFS_SIZE" != "0" ] && [ "$EFS_SIZE" != "null" ]; then
    EFS_GB=$(echo "scale=2; $EFS_SIZE / 1024 / 1024 / 1024" | bc)
    EFS_COST=$(echo "scale=2; $EFS_GB * 0.30" | bc)
    echo "  ✅ EFS Size: ${EFS_GB} GB"
    echo "  💰 EFS Cost: ~$${EFS_COST}/month (storage only)"
else
    echo "  ❌ No EFS filesystem found"
fi
echo ""

# Calculate total
echo "=========================================="
echo "COST SUMMARY"
echo "=========================================="
echo ""

if [ "$NODE_COUNT" -eq 0 ]; then
    echo "🟡 IDLE STATE (Cluster exists, no nodes running)"
    echo ""
    echo "Hourly costs:"
    echo "  - EKS Control Plane: $0.10/hour"
    echo "  - Nodes: $0.00/hour (scaled to 0)"
    echo "  - Load Balancer: $0.00/hour (deleted)"
    echo "  - Total: ~$0.10/hour"
    echo ""
    echo "Daily costs:"
    echo "  - Runtime: $2.40/day"
    echo "  - Storage (EFS): ~$0.50/day"
    echo "  - Total: ~$2.90/day = $87/month if left idle"
else
    echo "🟢 RUNNING STATE"
    echo ""
    HOURLY=$(echo "0.10 + ($NODE_COUNT * 0.0832) + 0.0225" | bc)
    DAILY=$(echo "$HOURLY * 24" | bc)
    MONTHLY=$(echo "$DAILY * 30" | bc)
    
    echo "Hourly costs:"
    echo "  - EKS Control Plane: $0.10/hour"
    echo "  - Nodes ($NODE_COUNT x t3.large): $$(echo "$NODE_COUNT * 0.0832" | bc)/hour"
    echo "  - Load Balancer: $0.0225/hour"
    echo "  - Bedrock: Pay-per-use (only when analyzing)"
    echo "  - Total: ~$${HOURLY}/hour"
    echo ""
    echo "For 4-hour usage:"
    echo "  - Session cost: $$(echo "$HOURLY * 4" | bc)"
    echo ""
    echo "If running 24/7 (not recommended):"
    echo "  - Daily: $${DAILY}/day"
    echo "  - Monthly: $${MONTHLY}/month"
fi

echo ""
echo "=========================================="
echo "RECOMMENDATIONS"
echo "=========================================="
echo ""

if [ "$NODE_COUNT" -gt 0 ]; then
    echo "⚠️  System is RUNNING - charges accumulating!"
    echo ""
    echo "To stop after your 4-hour session:"
    echo "  cd aws/scripts"
    echo "  ./stop-all-services.sh quick"
    echo ""
    echo "For complete shutdown (near-zero cost):"
    echo "  ./stop-all-services.sh full"
else
    echo "✅ System is STOPPED - minimal charges"
    echo ""
    echo "To completely eliminate idle costs:"
    echo "  cd aws/scripts"
    echo "  ./stop-all-services.sh full"
fi

echo ""
