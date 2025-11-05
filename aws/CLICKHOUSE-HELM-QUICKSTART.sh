#!/bin/bash

# ClickHouse Helm Installation - Quick Start
# Run this on your LOCAL MACHINE with kubectl configured for aws-hack cluster

set -e

echo "========================================="
echo "ClickHouse Helm Installation"
echo "Cluster: aws-hack"
echo "Namespace: l1-troubleshooting"
echo "========================================="

# Step 1: Add Helm repository
echo ""
echo "Step 1: Adding Bitnami Helm repository..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Step 2: Create namespace
echo ""
echo "Step 2: Creating namespace..."
 || echo "Namespace already exists"

# Step 3: Install ClickHouse
echo ""
echo "Step 3: Installing ClickHouse (this may take 5-10 minutes)..."
helm install clickhouse bitnami/clickhouse \
  --namespace l1-troubleshooting \
  --set auth.username=default \
  --set auth.password=foo \
  --set shards=1 \
  --set replicaCount=1 \
  --set zookeeper.enabled=false \
  --set keeper.enabled=true \
  --set persistence.enabled=true \
  --set persistence.storageClass=ebs-gp3 \
  --set persistence.size=50Gi \
  --set logsPersistence.enabled=true \
  --set logsPersistence.storageClass=ebs-gp3 \
  --set logsPersistence.size=10Gi \
  --set resources.requests.memory=2Gi \
  --set resources.requests.cpu=1000m \
  --set resources.limits.memory=4Gi \
  --set resources.limits.cpu=2000m \
  --wait \
  --timeout 10m

# Step 4: Verify installation
echo ""
echo "Step 4: Verifying installation..."
echo ""
echo "Pods:"
kubectl get pods -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse

echo ""
echo "PVCs:"
kubectl get pvc -n l1-troubleshooting

echo ""
echo "Service:"
kubectl get svc -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse

# Step 5: Initialize database
echo ""
echo "Step 5: Initializing database schema..."
CLICKHOUSE_POD=$(kubectl get pods -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

echo "Using pod: $CLICKHOUSE_POD"

kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "CREATE DATABASE IF NOT EXISTS l1_troubleshooting"

kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.anomalies (
    id String,
    timestamp DateTime,
    anomaly_type String,
    severity String,
    description String,
    source_file String,
    detection_method String,
    error_log String,
    packet_context String,
    confidence_score Float32,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, anomaly_type)
PARTITION BY toYYYYMM(timestamp)
"

kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "
CREATE TABLE IF NOT EXISTS l1-troubleshooting.sessions (
    session_id String,
    file_name String,
    file_type String,
    start_time DateTime,
    end_time DateTime,
    packets_processed Int32,
    anomalies_detected Int32,
    status String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (start_time, session_id)
"

kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.metrics (
    metric_name String,
    metric_value Float32,
    timestamp DateTime,
    tags Map(String, String),
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, metric_name)
PARTITION BY toYYYYMM(timestamp)
"

echo ""
echo "Verifying tables created:"
kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "SHOW TABLES FROM l1_troubleshooting"

echo ""
echo "========================================="
echo "✅ ClickHouse installation complete!"
echo "========================================="
echo ""
echo "Database: l1_troubleshooting"
echo "Tables: anomalies, sessions, metrics"
echo "Username: default"
echo "Password: foo"
echo ""
echo "Test connection:"
echo "kubectl exec -n l1-troubleshooting -it $CLICKHOUSE_POD -- clickhouse-client -u default --password foo"
