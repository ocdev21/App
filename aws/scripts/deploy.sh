#!/bin/bash
# Deploy L1 Troubleshooting System to AWS EKS
# Usage: ./deploy.sh <EKS_CLUSTER_NAME> <AWS_REGION>

set -e

# Configuration
EKS_CLUSTER_NAME=${1:-"l1-troubleshooting-cluster"}
AWS_REGION=${2:-"us-east-1"}

echo "=========================================="
echo "Deploying L1 Troubleshooting to AWS EKS"
echo "=========================================="
echo "Cluster: ${EKS_CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "=========================================="

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}

# Apply Kubernetes manifests in order
echo "Creating namespace..."
kubectl apply -f ../kubernetes/namespace.yaml

echo "Creating EFS StorageClass..."
kubectl apply -f ../kubernetes/storageclass-efs.yaml

echo "Creating EBS StorageClass for ClickHouse..."
kubectl apply -f ../kubernetes/storageclass-ebs.yaml

echo "Creating PersistentVolumeClaims..."
kubectl apply -f ../kubernetes/pvc.yaml

echo "Creating ClickHouse configuration..."
kubectl apply -f ../kubernetes/clickhouse-config.yaml

echo "Deploying ClickHouse StatefulSet..."
kubectl apply -f ../kubernetes/clickhouse-statefulset.yaml

echo "Creating ClickHouse NetworkPolicy..."
kubectl apply -f ../kubernetes/clickhouse-networkpolicy.yaml

echo "Waiting for ClickHouse to be ready (60 seconds)..."
sleep 60
kubectl wait --for=condition=ready pod -l app=clickhouse -n l1-troubleshooting --timeout=5m || echo "ClickHouse may need more time to start"

echo "Initializing ClickHouse database and tables..."
kubectl apply -f ../kubernetes/clickhouse-init-job.yaml

echo "Waiting for ClickHouse initialization to complete..."
kubectl wait --for=condition=complete job/clickhouse-init -n l1-troubleshooting --timeout=3m || echo "Initialization may need more time"

echo "Creating ConfigMap..."
kubectl apply -f ../kubernetes/configmap.yaml

echo "Creating Secrets..."
kubectl apply -f ../kubernetes/secrets.yaml

# NOTE: IAM Service Account for Bedrock is created via eksctl (see Step 3 in README.md)
# Do NOT apply bedrock-iam-role.yaml here as it contains placeholder ARN
# The eksctl command properly configures IRSA with the correct role ARN

echo "Creating Deployment..."
kubectl apply -f ../kubernetes/deployment.yaml

echo "Creating Service..."
kubectl apply -f ../kubernetes/service.yaml

echo "Creating Ingress..."
kubectl apply -f ../kubernetes/ingress.yaml

echo "Creating HorizontalPodAutoscaler..."
kubectl apply -f ../kubernetes/hpa.yaml

echo "=========================================="
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/l1-integrated-app -n l1-troubleshooting --timeout=5m

echo "=========================================="
echo "✅ Deployment completed successfully!"
echo "=========================================="

# Show deployment status
echo ""
echo "Pod Status:"
kubectl get pods -n l1-troubleshooting

echo ""
echo "Service Status:"
kubectl get svc -n l1-troubleshooting

echo ""
echo "Ingress Status:"
kubectl get ingress -n l1-troubleshooting

echo ""
echo "To get the ALB URL, run:"
echo "kubectl get ingress l1-integrated-ingress -n l1-troubleshooting -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
