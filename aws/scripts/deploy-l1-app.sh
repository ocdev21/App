#!/bin/bash

# Complete L1 Application Deployment to AWS EKS
# Builds Docker image, pushes to ECR, creates IAM role for Bedrock, and deploys to EKS

set -e

CLUSTER_NAME="aws-hack"
REGION="us-east-1"
NAMESPACE="l1-troubleshooting"
APP_NAME="l1-troubleshooting"

echo "========================================="
echo "L1 Application Deployment to EKS"
echo "========================================="

# Step 1: Get AWS Account ID
echo ""
echo "Step 1: Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Step 2: Create ECR Repository
echo ""
echo "Step 2: Creating ECR repository..."
aws ecr describe-repositories --repository-names $APP_NAME --region $REGION 2>/dev/null || \
aws ecr create-repository \
  --repository-name $APP_NAME \
  --region $REGION \
  --image-scanning-configuration scanOnPush=true

ECR_REPO_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${APP_NAME}"
echo "ECR Repository: $ECR_REPO_URI"

# Step 3: Login to ECR
echo ""
echo "Step 3: Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO_URI

# Step 4: Build Docker Image
echo ""
echo "Step 4: Building Docker image..."
echo "This may take 5-10 minutes..."
docker build -t $APP_NAME:latest -f aws/Dockerfile .
docker tag $APP_NAME:latest $ECR_REPO_URI:latest

# Step 5: Push to ECR
echo ""
echo "Step 5: Pushing image to ECR..."
docker push $ECR_REPO_URI:latest

# Step 6: Associate IAM OIDC provider (required for IRSA)
echo ""
echo "Step 6: Associating IAM OIDC provider with EKS cluster..."
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve 2>/dev/null || echo "OIDC provider already associated"

# Step 7: Create IAM Policy for Bedrock
echo ""
echo "Step 7: Creating IAM policy for AWS Bedrock access..."
POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

aws iam create-policy \
  --policy-name L1BedrockAccessPolicy \
  --policy-document "$POLICY_DOC" \
  --region $REGION 2>/dev/null || echo "Policy already exists"

# Step 8: Delete existing service account if it exists (to recreate with correct role)
echo ""
echo "Step 8: Cleaning up existing service account..."
eksctl delete iamserviceaccount \
  --name l1-app-sa \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --region $REGION 2>/dev/null || echo "No existing service account to delete"

# Step 9: Create IAM Role for Service Account (IRSA) with explicit role name
echo ""
echo "Step 9: Creating IAM role for EKS service account..."
eksctl create iamserviceaccount \
  --name l1-app-sa \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --role-name L1BedrockRole \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/L1BedrockAccessPolicy \
  --approve \
  --override-existing-serviceaccounts

echo "IAM Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/L1BedrockRole"

# Step 10: Update Kubernetes manifest with Account ID and deploy
echo ""
echo "Step 10: Deploying application to EKS..."
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" aws/kubernetes/l1-app-deployment.yaml | kubectl apply -f -

# Step 11: Wait for deployment
echo ""
echo "Step 11: Waiting for deployment to be ready..."
kubectl rollout status deployment/l1-app -n $NAMESPACE --timeout=5m

# Step 12: Get LoadBalancer URL
echo ""
echo "Step 12: Getting application URL..."
echo "Waiting for LoadBalancer to provision (this may take 2-3 minutes)..."
sleep 30

LB_HOSTNAME=$(kubectl get svc l1-app-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_HOSTNAME" ]; then
  echo "LoadBalancer not ready yet. Check status with:"
  echo "kubectl get svc l1-app-service -n $NAMESPACE"
else
  echo ""
  echo "========================================="
  echo "✅ Deployment Complete!"
  echo "========================================="
  echo ""
  echo "Application URL: http://$LB_HOSTNAME"
  echo ""
  echo "Verification Commands:"
  echo ""
  echo "1. Check pods:"
  echo "   kubectl get pods -n $NAMESPACE"
  echo ""
  echo "2. View logs:"
  echo "   kubectl logs -f deployment/l1-app -n $NAMESPACE"
  echo ""
  echo "3. Check ClickHouse connection:"
  echo "   kubectl exec deployment/l1-app -n $NAMESPACE -- curl -s http://clickhouse:9000"
  echo ""
  echo "4. Test Bedrock access (from pod):"
  echo "   kubectl exec deployment/l1-app -n $NAMESPACE -- curl -s http://localhost:8000/health"
  echo ""
  echo "Database: ClickHouse at clickhouse.l1-troubleshooting.svc.cluster.local"
  echo "AI Model: AWS Bedrock Nova Pro"
  echo ""
fi
