#!/bin/bash

# Clean up ClickHouse deployment (both Helm and manual)
# This script removes all ClickHouse resources to allow clean redeployment

set -e

echo "Cleaning up ClickHouse deployment..."

NAMESPACE="l1-troubleshooting"
RELEASE_NAME="clickhouse"

# Check if Helm release exists
if helm list -n $NAMESPACE 2>/dev/null | grep -q $RELEASE_NAME; then
    echo ""
    echo "Uninstalling Helm release: $RELEASE_NAME..."
    helm uninstall $RELEASE_NAME -n $NAMESPACE
fi

# Clean up manual deployment resources (if any)
echo ""
echo "Cleaning up manual deployment resources..."

kubectl delete statefulset clickhouse -n $NAMESPACE --ignore-not-found=true
kubectl delete pod -l app=clickhouse -n $NAMESPACE --ignore-not-found=true
kubectl delete pod -l app.kubernetes.io/name=clickhouse -n $NAMESPACE --ignore-not-found=true
kubectl delete service clickhouse -n $NAMESPACE --ignore-not-found=true
kubectl delete configmap clickhouse-config -n $NAMESPACE --ignore-not-found=true

# Delete PVCs (WARNING: This deletes all data!)
echo ""
echo "WARNING: Deleting PVCs will permanently delete all data!"
read -p "Delete PVCs? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete pvc -l app=clickhouse -n $NAMESPACE --ignore-not-found=true
    kubectl delete pvc -l app.kubernetes.io/name=clickhouse -n $NAMESPACE --ignore-not-found=true
    kubectl delete pvc clickhouse-data-clickhouse-0 -n $NAMESPACE --ignore-not-found=true
    kubectl delete pvc clickhouse-logs-clickhouse-0 -n $NAMESPACE --ignore-not-found=true
    echo "PVCs deleted"
else
    echo "Skipping PVC deletion - data preserved"
fi

# Delete NetworkPolicy
echo ""
kubectl delete networkpolicy clickhouse-access -n $NAMESPACE --ignore-not-found=true

echo ""
echo "✅ ClickHouse cleanup complete!"
echo ""
echo "Next step: Install ClickHouse using Helm"
echo "Run: aws/scripts/install-clickhouse-helm.sh"
