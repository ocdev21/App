
#!/bin/bash

echo "Cleaning up all ClickHouse resources"
echo "===================================="

# Delete ClickHouse installations
echo "Deleting ClickHouse installations..."
kubectl delete chi --all -n l1-app-ai --ignore-not-found=true
kubectl delete chi --all -n clickhouse-system --ignore-not-found=true

# Delete namespaces
echo "Deleting namespaces..."
kubectl delete namespace l1-app-ai --ignore-not-found=true
kubectl delete namespace clickhouse-system --ignore-not-found=true

# Uninstall Helm release
echo "Uninstalling ClickHouse operator Helm release..."
helm uninstall ch-operator -n clickhouse-system --ignore-not-found 2>/dev/null || true

# Remove Helm repository
echo "Removing ClickHouse operator Helm repository..."
helm repo remove clickhouse-operator

# Delete any remaining CRDs
echo "Deleting ClickHouse CRDs..."
kubectl delete crd clickhouseinstallations.clickhouse.altinity.com --ignore-not-found=true
kubectl delete crd clickhouseinstallationtemplates.clickhouse.altinity.com --ignore-not-found=true
kubectl delete crd clickhouseoperatorconfigurations.clickhouse.altinity.com --ignore-not-found=true

# Delete any remaining PVCs
echo "Deleting any remaining PVCs..."
kubectl delete pvc --all -n l1-app-ai --ignore-not-found=true

# Wait a moment for resources to be cleaned up
echo "Waiting for cleanup to complete..."
sleep 10

echo "Cleanup completed!"
echo ""
echo "You can now run './simple-install.sh' for a fresh installation"
