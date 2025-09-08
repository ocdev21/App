
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

echo "🚀 Starting ClickHouse installation..."

# Make scripts executable
chmod +x install-clickhouse.sh setup-database.sh

# Step 1: Install ClickHouse operator
echo "Step 1: Installing ClickHouse operator..."
./install-clickhouse.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to install ClickHouse operator"
    exit 1
fi

# Step 2: Install ClickHouse instance
echo "Step 2: Installing ClickHouse instance..."
kubectl apply -f clickhouse-installation.yaml

if [ $? -ne 0 ]; then
    echo "❌ Failed to install ClickHouse instance"
    exit 1
fi

# Step 3: Wait for ClickHouse to be ready
echo "Step 3: Waiting for ClickHouse to be ready..."
sleep 30

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
echo "   Port forward: kubectl port-forward svc/chi-clickhouse-ai-clickhouse-cluster-0-0 8123:8123 -n l1-app-ai"
echo "   Test connection: curl http://localhost:8123/ping"
echo ""
echo "🔧 Configuration:"
echo "   - Namespace: l1-app-ai"
echo "   - Database: l1_anomaly_detection"
echo "   - Service: chi-clickhouse-ai-clickhouse-cluster-0-0"
echo "   - HTTP Port: 8123"
echo "   - TCP Port: 9000"
