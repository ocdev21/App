
#!/bin/bash

echo "Installing ClickHouse using Helm and ClickHouse Operator"
echo "======================================================="

# Add ClickHouse operator helm repository
echo "Adding ClickHouse operator helm repository..."
helm repo add clickhouse-operator https://docs.altinity.com/clickhouse-operator/

# Update helm repositories
echo "Updating helm repositories..."
helm repo update

# Create namespace for ClickHouse operator
echo "Creating clickhouse-system namespace..."
kubectl create namespace clickhouse-system --dry-run=client -o yaml | kubectl apply -f -

# Install ClickHouse operator
echo "Installing ClickHouse operator..."
helm install clickhouse-operator clickhouse-operator/altinity-clickhouse-operator \
  --namespace clickhouse-system \
  --set operator.image.tag=0.21.3

# Wait for operator to be ready
echo "Waiting for ClickHouse operator to be ready..."
kubectl wait --for=condition=available deployment/clickhouse-operator -n clickhouse-system --timeout=300s

# Create namespace for ClickHouse
echo "Creating l1-app-ai namespace..."
kubectl create namespace l1-app-ai --dry-run=client -o yaml | kubectl apply -f -

echo "✅ ClickHouse operator installation completed!"
echo ""
echo "Next steps:"
echo "1. Apply the ClickHouse installation: kubectl apply -f clickhouse-installation.yaml"
echo "2. Check installation status: kubectl get chi -n l1-app-ai"
echo "3. Check pods: kubectl get pods -n l1-app-ai"
