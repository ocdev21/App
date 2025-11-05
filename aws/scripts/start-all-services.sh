#!/bin/bash
# Start All L1 Services
# Usage: ./start-all-services.sh [quick|full]
#
# quick: Restart existing cluster (faster, use after quick shutdown)
# full:  Create new cluster from scratch (use after full shutdown)

set -e

MODE=${1:-quick}
CLUSTER_NAME="l1-troubleshooting-cluster"
REGION="us-east-1"
ACCOUNT_ID="012351853258"

echo "=========================================="
echo "L1 Services Startup Script"
echo "=========================================="
echo "Mode: $MODE"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "=========================================="
echo ""

if [ "$MODE" == "full" ]; then
    echo "⚠️  FULL STARTUP MODE - Creating new EKS cluster"
    echo "This will take approximately 20-25 minutes"
    echo ""
    
    # Create new cluster
    echo "Step 1: Creating EKS cluster..."
    eksctl create cluster \
      --name ${CLUSTER_NAME} \
      --region ${REGION} \
      --nodegroup-name standard-workers \
      --node-type t3.large \
      --nodes 2 \
      --nodes-min 2 \
      --nodes-max 5 \
      --managed
    
    echo ""
    echo "Step 2: Installing AWS Load Balancer Controller..."
    
    # Download IAM policy
    curl -o /tmp/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
    
    # Create or update policy
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file:///tmp/iam_policy.json 2>/dev/null || \
        echo "  Policy already exists, continuing..."
    
    # Create service account
    eksctl create iamserviceaccount \
      --cluster=${CLUSTER_NAME} \
      --namespace=kube-system \
      --name=aws-load-balancer-controller \
      --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
      --override-existing-serviceaccounts \
      --approve
    
    # Install controller
    helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
    helm repo update
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      --set clusterName=${CLUSTER_NAME} \
      --set serviceAccount.create=false \
      --set serviceAccount.name=aws-load-balancer-controller
    
    echo ""
    echo "Step 3: Installing EFS CSI Driver..."
    
    # Download EFS policy
    curl -o /tmp/efs-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json
    
    # Create or update policy
    aws iam create-policy \
        --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
        --policy-document file:///tmp/efs-iam-policy.json 2>/dev/null || \
        echo "  Policy already exists, continuing..."
    
    # Create service account
    eksctl create iamserviceaccount \
        --cluster ${CLUSTER_NAME} \
        --namespace kube-system \
        --name efs-csi-controller-sa \
        --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AmazonEKS_EFS_CSI_Driver_Policy \
        --approve
    
    # Install driver
    helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/ 2>/dev/null || true
    helm repo update
    helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
        --namespace kube-system \
        --set controller.serviceAccount.create=false \
        --set controller.serviceAccount.name=efs-csi-controller-sa
    
    echo ""
    echo "Step 4: Creating Bedrock IAM service account..."
    
    # Create Bedrock service account
    eksctl create iamserviceaccount \
      --name l1-bedrock-sa \
      --namespace l1-troubleshooting \
      --cluster ${CLUSTER_NAME} \
      --region ${REGION} \
      --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/L1BedrockAccessPolicy \
      --approve \
      --override-existing-serviceaccounts
    
    echo ""
    echo "⚠️  MANUAL STEP REQUIRED:"
    echo "You need to update kubernetes/storageclass-efs.yaml with your EFS ID"
    echo "Then run: ./deploy.sh ${CLUSTER_NAME} ${REGION}"
    
else
    # Quick restart - scale up existing cluster
    echo "Step 1: Updating kubeconfig..."
    aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
    
    echo ""
    echo "Step 2: Scaling node groups to 2 nodes..."
    NODEGROUPS=$(eksctl get nodegroup --cluster ${CLUSTER_NAME} --region ${REGION} -o json | jq -r '.[].Name' 2>/dev/null || echo "")
    
    if [ -n "$NODEGROUPS" ]; then
        for NG in $NODEGROUPS; do
            echo "  Scaling nodegroup: $NG to 2 nodes"
            eksctl scale nodegroup \
                --cluster ${CLUSTER_NAME} \
                --region ${REGION} \
                --name $NG \
                --nodes 2 \
                --nodes-min 2 \
                --nodes-max 5
        done
    else
        echo "  Error: No nodegroups found!"
        exit 1
    fi
    
    echo ""
    echo "Step 3: Waiting for nodes to be ready (60 seconds)..."
    sleep 60
    kubectl get nodes
    
    echo ""
    echo "Step 4: Recreating Bedrock IAM service account..."
    eksctl create iamserviceaccount \
      --name l1-bedrock-sa \
      --namespace l1-troubleshooting \
      --cluster ${CLUSTER_NAME} \
      --region ${REGION} \
      --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/L1BedrockAccessPolicy \
      --approve \
      --override-existing-serviceaccounts 2>/dev/null || echo "  Service account already exists"
    
    echo ""
    echo "Step 5: Deploying application..."
    cd "$(dirname "$0")"
    ./deploy.sh ${CLUSTER_NAME} ${REGION}
    
    echo ""
    echo "Step 6: Waiting for deployment to be ready..."
    kubectl rollout status deployment/l1-integrated-app -n l1-troubleshooting --timeout=5m
    
    echo ""
    echo "Step 7: Getting application URL..."
    sleep 30  # Wait for ALB to provision
    ALB_URL=$(kubectl get ingress l1-integrated-ingress -n l1-troubleshooting -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    if [ "$ALB_URL" != "pending" ]; then
        echo ""
        echo "=========================================="
        echo "✅ APPLICATION READY!"
        echo "=========================================="
        echo "Access your L1 Troubleshooting UI at:"
        echo "  http://$ALB_URL"
    else
        echo ""
        echo "⚠️  ALB is still provisioning (takes 2-3 minutes)"
        echo "Run this to get the URL when ready:"
        echo "  kubectl get ingress -n l1-troubleshooting"
    fi
fi

echo ""
echo "Timestamp: $(date)"
echo "=========================================="
