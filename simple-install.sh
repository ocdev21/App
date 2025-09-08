
#!/bin/bash

echo "L1 Troubleshooting AI - Simple ClickHouse Installation"
echo "====================================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is required but not installed."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is required but not installed."
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo "🧹 Cleaning up any existing ClickHouse resources..."
chmod +x cleanup-clickhouse.sh
./cleanup-clickhouse.sh

echo ""
echo "🚀 Starting fresh ClickHouse installation..."

# Make scripts executable
chmod +x install-clickhouse.sh setup-database.sh

# Step 1: Install ClickHouse operator
echo "Step 1: Installing ClickHouse operator..."
./install-clickhouse.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to install ClickHouse operator"
    exit 1
fi

# Wait for operator to be fully ready
echo "Waiting for ClickHouse operator to be fully ready..."
sleep 30

# Step 2: Install ClickHouse instance
echo "Step 2: Installing ClickHouse instance..."
kubectl apply -f clickhouse-installation.yaml

if [ $? -ne 0 ]; then
    echo "❌ Failed to install ClickHouse instance"
    exit 1
fi

# Step 3: Wait for ClickHouse to be ready
echo "Step 3: Waiting for ClickHouse to be ready..."
echo "This may take a few minutes..."

# Check if CHI resource was created
echo "Checking CHI resource creation..."
kubectl get chi -n l1-app-ai

# Wait for pods to appear first
echo "Waiting for ClickHouse pods to be created..."
timeout 300 bash -c 'while [[ $(kubectl get pods -n l1-app-ai -l clickhouse.altinity.com/chi=ch-ai --no-headers 2>/dev/null | wc -l) -eq 0 ]]; do sleep 10; echo "Still waiting for pods..."; done'

# Show pod status
echo "Current pod status:"
kubectl get pods -n l1-app-ai -l clickhouse.altinity.com/chi=ch-ai

# Wait for pods to be ready with timeout
echo "Waiting for ClickHouse pods to be ready (max 10 minutes)..."
kubectl wait --for=condition=ready pod -l clickhouse.altinity.com/chi=ch-ai -n l1-app-ai --timeout=600s

# If pods are not ready, show diagnostics
if [ $? -ne 0 ]; then
    echo "⚠️  Pods are not ready yet. Showing diagnostics:"
    echo "Pod status:"
    kubectl get pods -n l1-app-ai -l clickhouse.altinity.com/chi=ch-ai -o wide
    echo "Pod events:"
    kubectl get events -n l1-app-ai --sort-by='.lastTimestamp' | tail -20
    echo "CHI resource status:"
    kubectl describe chi ch-ai -n l1-app-ai
    echo "You may need to check the logs with: kubectl logs -l clickhouse.altinity.com/chi=ch-ai -n l1-app-ai"
    exit 1
fi

# Step 4: Setup database
echo "Step 4: Setting up database..."
./setup-database.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to setup database"
    exit 1
fi

echo ""
echo "🎉 ClickHouse installation completed successfully!"
echo ""
echo "📋 Quick Start Commands:"
echo "   Check status: kubectl get chi -n l1-app-ai"
echo "   View pods: kubectl get pods -n l1-app-ai"
echo "   Port forward: kubectl port-forward svc/chi-ch-ai-ch-cluster-0-0 8123:8123 -n l1-app-ai"
echo "   Test connection: curl http://localhost:8123/ping"
echo ""
echo "🔧 Configuration:"
echo "   - Namespace: l1-app-ai"
echo "   - Database: l1_anomaly_detection"
echo "   - Service: chi-ch-ai-ch-cluster-0-0"
echo "   - HTTP Port: 8123"
echo "   - TCP Port: 9000"
