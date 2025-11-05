#!/bin/bash

# Clean up failed ClickHouse deployment
# This script removes all ClickHouse resources to allow clean redeployment

set -e

echo "Cleaning up failed ClickHouse deployment..."

NAMESPACE="l1-troubleshooting"

echo ""
echo "Deleting ClickHouse StatefulSet..."
kubectl delete statefulset clickhouse -n $NAMESPACE --ignore-not-found=true

echo ""
echo "Deleting ClickHouse pods..."
kubectl delete pod -l app=clickhouse -n $NAMESPACE --ignore-not-found=true

echo ""
echo "Deleting ClickHouse PVCs..."
kubectl delete pvc -l app=clickhouse -n $NAMESPACE --ignore-not-found=true
kubectl delete pvc clickhouse-data-clickhouse-0 -n $NAMESPACE --ignore-not-found=true
kubectl delete pvc clickhouse-logs-clickhouse-0 -n $NAMESPACE --ignore-not-found=true

echo ""
echo "Deleting ClickHouse Service..."
kubectl delete service clickhouse -n $NAMESPACE --ignore-not-found=true

echo ""
echo "Deleting ClickHouse ConfigMap..."
kubectl delete configmap clickhouse-config -n $NAMESPACE --ignore-not-found=true

echo ""
echo "Deleting ClickHouse NetworkPolicy..."
kubectl delete networkpolicy clickhouse-access -n $NAMESPACE --ignore-not-found=true

echo ""
echo "✅ ClickHouse cleanup complete!"
echo ""
echo "Waiting 10 seconds for resources to fully terminate..."
sleep 10

echo ""
echo "Next step: Redeploy ClickHouse with working EBS CSI driver"
echo "Run: kubectl apply -f aws/kubernetes/clickhouse-config.yaml"
echo "      kubectl apply -f aws/kubernetes/clickhouse-statefulset.yaml"
echo "      kubectl apply -f aws/kubernetes/clickhouse-networkpolicy.yaml"
