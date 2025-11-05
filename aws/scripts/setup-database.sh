#!/bin/bash

# Complete ClickHouse Database Setup for L1 Troubleshooting System
# Creates credentials secret and initializes database schema

set -e

NAMESPACE="l1-troubleshooting"
CLICKHOUSE_PASSWORD="defaultpass"

echo "========================================="
echo "ClickHouse Database Setup"
echo "========================================="

# Step 1: Create credentials secret
echo ""
echo "Step 1: Creating ClickHouse credentials secret..."
kubectl delete secret clickhouse-credentials -n $NAMESPACE 2>/dev/null || true
kubectl create secret generic clickhouse-credentials \
  -n $NAMESPACE \
  --from-literal=username=default \
  --from-literal=password=$CLICKHOUSE_PASSWORD

echo "✓ Secret created"

# Step 2: Get ClickHouse pod
echo ""
echo "Step 2: Finding ClickHouse pod..."
CLICKHOUSE_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

if [ -z "$CLICKHOUSE_POD" ]; then
    echo "Error: ClickHouse pod not found"
    exit 1
fi

echo "✓ Using pod: $CLICKHOUSE_POD"

# Step 3: Create database
echo ""
echo "Step 3: Creating l1_troubleshooting database..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE DATABASE IF NOT EXISTS l1_troubleshooting
"
echo "✓ Database created"

# Step 4: Create anomalies table
echo ""
echo "Step 4: Creating anomalies table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.anomalies (
    id String,
    timestamp DateTime,
    anomaly_type String,
    severity String,
    description String,
    source_file String,
    detection_method String DEFAULT 'rule-based',
    error_log String DEFAULT '',
    packet_context String DEFAULT '',
    confidence_score Float32 DEFAULT 0.0,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, anomaly_type)
PARTITION BY toYYYYMM(timestamp)
"
echo "✓ Anomalies table created"

# Step 5: Create sessions table
echo ""
echo "Step 5: Creating sessions table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.sessions (
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
echo "✓ Sessions table created"

# Step 6: Create metrics table
echo ""
echo "Step 6: Creating metrics table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
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
echo "✓ Metrics table created"

# Step 7: Verify setup
echo ""
echo "Step 7: Verifying database setup..."
echo ""
echo "Databases:"
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "SHOW DATABASES"

echo ""
echo "Tables in l1_troubleshooting:"
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "SHOW TABLES FROM l1_troubleshooting"

echo ""
echo "========================================="
echo "✅ ClickHouse Database Setup Complete!"
echo "========================================="
echo ""
echo "Database: l1_troubleshooting"
echo "Tables: anomalies, sessions, metrics"
echo "Password: $CLICKHOUSE_PASSWORD"
echo ""
echo "To test connection:"
echo "kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password $CLICKHOUSE_PASSWORD -q 'SELECT version()'"
