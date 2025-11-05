#!/bin/bash

# Setup ClickHouse with EFS Persistent Storage on EKS Auto Mode
# Run this script on your local machine with kubectl configured for aws-hack cluster

set -e

CLUSTER_NAME="aws-hack"
REGION="us-east-1"
NAMESPACE="l1-troubleshooting"

echo "========================================="
echo "ClickHouse with EFS Setup"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "========================================="

# Step 1: Get VPC and Subnet Info
echo ""
echo "Step 1: Getting VPC and subnet information..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "VPC ID: $VPC_ID"

SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.subnetIds" --output text)
echo "Subnets: $SUBNET_IDS"

# Step 2: Create EFS Security Group
echo ""
echo "Step 2: Creating EFS security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name l1-efs-sg-$(date +%s) \
  --description "Security group for L1 ClickHouse EFS" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --output text --query 'GroupId')

echo "Security Group ID: $SG_ID"

VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --region $REGION --query 'Vpcs[0].CidrBlock' --output text)
echo "VPC CIDR: $VPC_CIDR"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr $VPC_CIDR \
  --region $REGION

echo "Authorized NFS traffic from VPC"

# Step 3: Create EFS Filesystem
echo ""
echo "Step 3: Creating EFS filesystem..."
EFS_ID=$(aws efs create-file-system \
  --creation-token l1-clickhouse-$(date +%s) \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --region $REGION \
  --tags Key=Name,Value=l1-clickhouse-efs \
  --output text --query 'FileSystemId')

echo "EFS ID: $EFS_ID"

echo "Waiting for EFS to be available..."
sleep 10
EFS_STATE=$(aws efs describe-file-systems --file-system-id $EFS_ID --region $REGION --query 'FileSystems[0].LifeCycleState' --output text)
echo "EFS State: $EFS_STATE"

# Step 4: Create Mount Targets
echo ""
echo "Step 4: Creating mount targets for each subnet..."
for SUBNET in $SUBNET_IDS; do
  echo "Creating mount target in subnet: $SUBNET"
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $SUBNET \
    --security-groups $SG_ID \
    --region $REGION || echo "Mount target may already exist"
done

echo "Waiting for mount targets to be available..."
sleep 20

# Step 5: Create/Update EFS Storage Class
echo ""
echo "Step 5: Creating EFS StorageClass..."

kubectl delete storageclass efs-sc --ignore-not-found=true

cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: $EFS_ID
  directoryPerms: "700"
EOF

echo "StorageClass created"

# Step 6: Install ClickHouse with EFS
echo ""
echo "Step 6: Installing ClickHouse with EFS persistent storage..."

helm uninstall clickhouse -n $NAMESPACE 2>/dev/null || true

echo "Waiting for cleanup..."
sleep 10

helm install clickhouse bitnami/clickhouse \
  --namespace $NAMESPACE \
  --set auth.username=default \
  --set auth.password=defaultpass \
  --set shards=1 \
  --set replicaCount=1 \
  --set persistence.enabled=true \
  --set persistence.storageClass=efs-sc \
  --set persistence.size=50Gi \
  --set zookeeper.enabled=false \
  --set keeper.enabled=false \
  --wait \
  --timeout 10m

# Step 7: Verify Installation
echo ""
echo "========================================="
echo "✅ Installation Complete!"
echo "========================================="
echo ""
echo "Verification:"
echo ""
echo "Pods:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse

echo ""
echo "PVCs:"
kubectl get pvc -n $NAMESPACE

echo ""
echo "Service:"
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=clickhouse

echo ""
echo "========================================="
echo "Resources Created:"
echo "EFS ID: $EFS_ID"
echo "Security Group: $SG_ID"
echo "Storage Class: efs-sc"
echo "========================================="
echo ""
echo "To connect to ClickHouse:"
echo "CLICKHOUSE_POD=\$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')"
echo "kubectl exec -n $NAMESPACE -it \$CLICKHOUSE_POD -- clickhouse-client -u default --password defaultpass"
