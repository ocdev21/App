#!/bin/bash

# Install ClickHouse using Bitnami Helm Chart
# This script installs ClickHouse with persistent EBS storage on AWS EKS

set -e

echo "Installing ClickHouse using Bitnami Helm Chart..."

NAMESPACE="l1-troubleshooting"
RELEASE_NAME="clickhouse"
CHART="bitnami/clickhouse"

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    echo "Error: Helm is not installed. Please install Helm first."
    echo "Visit: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Add Bitnami Helm repository
echo ""
echo "Adding Bitnami Helm repository..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Get script directory for proper path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="$SCRIPT_DIR/../helm/clickhouse-values.yaml"

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo ""
    echo "Creating namespace $NAMESPACE..."
    kubectl create namespace $NAMESPACE
fi

# Generate secure random password if secret doesn't exist
if ! kubectl get secret -n $NAMESPACE clickhouse-credentials &> /dev/null; then
    echo ""
    echo "Generating secure ClickHouse password..."
    CLICKHOUSE_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
    kubectl create secret generic clickhouse-credentials \
        --namespace $NAMESPACE \
        --from-literal=username=default \
        --from-literal=password="$CLICKHOUSE_PASSWORD"
    echo "Password stored in Kubernetes secret: clickhouse-credentials"
else
    echo ""
    echo "Using existing ClickHouse credentials from secret"
fi

# Check if ClickHouse is already installed
if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
    echo ""
    echo "ClickHouse is already installed. Upgrading..."
    helm upgrade $RELEASE_NAME $CHART \
        --namespace $NAMESPACE \
        --values "$VALUES_FILE" \
        --set auth.existingSecret=clickhouse-credentials \
        --wait \
        --timeout 10m
else
    echo ""
    echo "Installing ClickHouse..."
    helm install $RELEASE_NAME $CHART \
        --namespace $NAMESPACE \
        --values "$VALUES_FILE" \
        --set auth.existingSecret=clickhouse-credentials \
        --wait \
        --timeout 10m
fi

echo ""
echo "✅ ClickHouse installation complete!"
echo ""
echo "Checking deployment status..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse
kubectl get pvc -n $NAMESPACE

echo ""
echo "ClickHouse service:"
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=clickhouse

echo ""
echo "Testing ClickHouse connection..."
CLICKHOUSE_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

if [ -n "$CLICKHOUSE_POD" ]; then
    echo "Running query on pod: $CLICKHOUSE_POD"
    kubectl exec -n $NAMESPACE -it $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "SELECT version()" || echo "Connection test failed - pod may still be starting"
else
    echo "No ClickHouse pod found yet"
fi

echo ""
echo "Next steps:"
echo "1. Initialize database: aws/scripts/init-clickhouse-db.sh"
echo "2. Apply NetworkPolicy: kubectl apply -f aws/kubernetes/clickhouse-networkpolicy.yaml"
