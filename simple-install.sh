
#!/bin/bash

echo "L1 Troubleshooting AI - Simple ClickHouse Installation"
echo "====================================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is required but not installed."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm is required but not installed."
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo "Cleaning up any existing ClickHouse resources..."
chmod +x cleanup-clickhouse.sh
./cleanup-clickhouse.sh

echo ""
echo "Starting fresh ClickHouse installation..."

# Make scripts executable
chmod +x install-clickhouse.sh setup-database.sh

# Step 1: Install ClickHouse operator
echo "Step 1: Installing ClickHouse operator..."
./install-clickhouse.sh

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install ClickHouse operator"
    exit 1
fi

# Wait for operator to be fully ready
echo "Waiting for ClickHouse operator to be fully ready..."
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=altinity-clickhouse-operator -n clickhouse-system --timeout=300s

if [ $? -ne 0 ]; then
    echo "ERROR: ClickHouse operator not ready"
    exit 1
fi

# Step 2: Install ClickHouse instance
echo "Step 2: Installing ClickHouse instance..."
kubectl apply -f clickhouse-installation.yaml

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install ClickHouse instance"
    exit 1
fi

# Step 3: Wait for ClickHouse to be ready with better monitoring
echo "Step 3: Waiting for ClickHouse to be ready..."
echo "This may take a few minutes..."

# Check if CHI resource was created
echo "Checking CHI resource creation..."
kubectl get chi -n l1-app-ai

# Wait for CHI to be ready (not just pods)
echo "Waiting for CHI resource to be ready..."
timeout 600 bash -c 'while [[ $(kubectl get chi clickhouse-single -n l1-app-ai -o jsonpath="{.status.state}" 2>/dev/null) != "Completed" ]]; do 
    echo "CHI Status: $(kubectl get chi clickhouse-single -n l1-app-ai -o jsonpath="{.status.state}" 2>/dev/null || echo "Not found")"
    kubectl get chi clickhouse-single -n l1-app-ai -o wide 2>/dev/null || echo "CHI not found yet"
    sleep 15
done'

# Show current status
echo "Current CHI status:"
kubectl get chi clickhouse-single -n l1-app-ai -o wide

echo "Current pod status:"
kubectl get pods -n l1-app-ai

# Wait for pods to be ready with timeout
echo "Waiting for ClickHouse pods to be ready (max 10 minutes)..."
kubectl wait --for=condition=ready pod -l clickhouse.altinity.com/chi=clickhouse-single -n l1-app-ai --timeout=600s

# If pods are not ready, show diagnostics
if [ $? -ne 0 ]; then
    echo "WARNING: Pods are not ready yet. Showing diagnostics:"
    echo "Pod status:"
    kubectl get pods -n l1-app-ai -o wide
    echo "Pod events:"
    kubectl get events -n l1-app-ai --sort-by='.lastTimestamp' | tail -20
    echo "CHI resource status:"
    kubectl describe chi clickhouse-single -n l1-app-ai
    echo "Checking for any pods with logs:"
    for pod in $(kubectl get pods -n l1-app-ai -o name); do
        echo "=== Logs for $pod ==="
        kubectl logs $pod -n l1-app-ai --tail=10 2>/dev/null || echo "No logs available"
    done
    exit 1
fi

# Step 4: Setup database
echo "Step 4: Setting up database..."
./setup-database.sh

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to setup database"
    exit 1
fi

echo ""
echo "ClickHouse installation completed successfully!"
echo ""
echo "Quick Start Commands:"
echo "   Check status: kubectl get chi -n l1-app-ai"
echo "   View pods: kubectl get pods -n l1-app-ai"
echo "   Port forward: kubectl port-forward svc/chi-clickhouse-single-clickhouse-0-0 9000:9000 -n l1-app-ai"
echo "   Test connection: curl http://localhost:9000/ping"
echo ""
echo "Configuration:"
echo "   - Namespace: l1-app-ai"
echo "   - Database: l1_anomaly_detection"
echo "   - Service: chi-clickhouse-single-clickhouse-0-0"
echo "   - HTTP Port: 9000"
echo "   - TCP Port: 9000"
echo "   - Username: default"
echo "   - Password: defaultpass"
