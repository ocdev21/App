#!/bin/bash

# Install EBS CSI Driver for ClickHouse Persistent Storage
# This script installs the AWS EBS CSI driver addon required for dynamic EBS volume provisioning

set -e

echo "Installing EBS CSI Driver on aws-hack cluster..."

# Get cluster name and region
CLUSTER_NAME="aws-hack"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Account: $ACCOUNT_ID"

# Create IAM role for EBS CSI driver
echo ""
echo "Creating IAM role for EBS CSI driver..."

# Create trust policy for OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | sed -e 's|^https://||')

cat > /tmp/ebs-csi-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

# Create IAM role
ROLE_NAME="AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}"
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/ebs-csi-trust-policy.json \
  --description "IAM role for EBS CSI driver on $CLUSTER_NAME" \
  --region $AWS_REGION || echo "Role may already exist"

# Attach AWS managed policy
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --region $AWS_REGION || echo "Policy may already be attached"

echo ""
echo "Installing EBS CSI driver addon..."

# Install EBS CSI driver as EKS addon
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --region $AWS_REGION || echo "Addon may already exist - updating..."

# If addon exists, update it
aws eks update-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --region $AWS_REGION || true

echo ""
echo "Waiting for EBS CSI driver to be active..."
aws eks wait addon-active \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $AWS_REGION

echo ""
echo "✅ EBS CSI driver installation complete!"
echo ""
echo "Verifying installation..."
kubectl get pods -n kube-system | grep ebs-csi

echo ""
echo "Next step: Clean up failed ClickHouse deployment and redeploy"
echo "Run: aws/scripts/cleanup-clickhouse.sh"
