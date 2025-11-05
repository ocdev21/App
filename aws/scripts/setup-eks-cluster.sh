#!/bin/bash
# Create AWS EKS Cluster for L1 Troubleshooting System
# Usage: ./setup-eks-cluster.sh <CLUSTER_NAME> <AWS_REGION>

set -e

# Configuration
CLUSTER_NAME=${1:-"l1-troubleshooting-cluster"}
AWS_REGION=${2:-"us-east-1"}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
NODE_TYPE="t3.medium"
MIN_NODES=1
MAX_NODES=3
DESIRED_NODES=2

echo "=========================================="
echo "Creating EKS Cluster for L1 Troubleshooting"
echo "=========================================="
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "Account ID: ${AWS_ACCOUNT_ID}"
echo "Node Type: ${NODE_TYPE}"
echo "Nodes: ${MIN_NODES}-${MAX_NODES} (desired: ${DESIRED_NODES})"
echo "=========================================="
echo ""
echo "⏱️  This will take approximately 20-25 minutes"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo "❌ eksctl is not installed. Installing..."
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    echo "✅ eksctl installed"
fi

# Create EKS cluster
echo ""
echo "📦 Step 1/5: Creating EKS cluster and node group..."
echo "This step takes ~15-20 minutes..."

eksctl create cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --version 1.28 \
  --nodegroup-name standard-workers \
  --node-type ${NODE_TYPE} \
  --nodes ${DESIRED_NODES} \
  --nodes-min ${MIN_NODES} \
  --nodes-max ${MAX_NODES} \
  --managed \
  --with-oidc \
  --ssh-access=false \
  --tags "Environment=production,Project=l1-troubleshooting,ManagedBy=eksctl"

echo "✅ EKS cluster created successfully"

# Update kubeconfig
echo ""
echo "📦 Step 2/5: Updating kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}
echo "✅ kubeconfig updated"

# Install AWS Load Balancer Controller
echo ""
echo "📦 Step 3/5: Installing AWS Load Balancer Controller..."

# Download IAM policy
curl -o /tmp/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.2/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME} \
    --policy-document file:///tmp/iam_policy.json \
    --region ${AWS_REGION} 2>/dev/null || echo "Policy already exists"

# Create service account
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole-${CLUSTER_NAME} \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME} \
  --approve \
  --region ${AWS_REGION} \
  --override-existing-serviceaccounts 2>/dev/null || echo "Service account already exists"

# Install controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=${AWS_REGION} \
  --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text) \
  2>/dev/null || helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=${AWS_REGION} \
  --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "✅ AWS Load Balancer Controller installed"

# Install EBS CSI Driver
echo ""
echo "📦 Step 4/5: Installing EBS CSI Driver..."

# Create IAM role for EBS CSI driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-name AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME} \
  --override-existing-serviceaccounts 2>/dev/null || echo "EBS CSI service account already exists"

# Install EBS CSI driver addon
aws eks create-addon \
  --cluster-name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME} \
  2>/dev/null || echo "EBS CSI driver addon already exists"

# Wait for addon to be active
echo "Waiting for EBS CSI driver to become active..."
sleep 30

echo "✅ EBS CSI Driver installed"

# Install EFS CSI Driver
echo ""
echo "📦 Step 5/5: Installing EFS CSI Driver..."

# Create IAM policy for EFS
cat > /tmp/efs-csi-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:CreateAccessPoint"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/efs.csi.aws.com/cluster": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "elasticfilesystem:DeleteAccessPoint",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
        }
      }
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy_${CLUSTER_NAME} \
    --policy-document file:///tmp/efs-csi-policy.json \
    --region ${AWS_REGION} 2>/dev/null || echo "EFS policy already exists"

# Create service account for EFS CSI
eksctl create iamserviceaccount \
  --cluster ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --namespace kube-system \
  --name efs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEKS_EFS_CSI_Driver_Policy_${CLUSTER_NAME} \
  --approve \
  --role-name AmazonEKS_EFS_CSI_DriverRole_${CLUSTER_NAME} \
  --override-existing-serviceaccounts 2>/dev/null || echo "EFS CSI service account already exists"

# Install EFS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"

echo "✅ EFS CSI Driver installed"

# Verify installation
echo ""
echo "=========================================="
echo "✅ EKS Cluster Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Cluster Information:"
kubectl cluster-info
echo ""
echo "📋 Nodes:"
kubectl get nodes
echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. Create and push Docker image:"
echo "   cd aws/scripts"
echo "   ./build-and-push.sh ${AWS_ACCOUNT_ID} ${AWS_REGION}"
echo ""
echo "2. Create IAM role for Bedrock access:"
echo "   eksctl create iamserviceaccount \\"
echo "     --name bedrock-access-sa \\"
echo "     --namespace l1-troubleshooting \\"
echo "     --cluster ${CLUSTER_NAME} \\"
echo "     --region ${AWS_REGION} \\"
echo "     --attach-policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess \\"
echo "     --approve \\"
echo "     --override-existing-serviceaccounts"
echo ""
echo "3. Create EFS filesystem for model storage:"
echo "   VPC_ID=\$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)"
echo "   aws efs create-file-system \\"
echo "     --region ${AWS_REGION} \\"
echo "     --performance-mode generalPurpose \\"
echo "     --throughput-mode bursting \\"
echo "     --encrypted \\"
echo "     --tags Key=Name,Value=l1-troubleshooting-efs"
echo ""
echo "4. Deploy the application:"
echo "   ./deploy.sh ${CLUSTER_NAME} ${AWS_REGION}"
echo ""
echo "=========================================="
