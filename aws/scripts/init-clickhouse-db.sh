#!/bin/bash

# Initialize ClickHouse Database for L1 Troubleshooting System
# Creates database and tables required for anomaly storage

set -e

echo "Initializing ClickHouse database schema..."

NAMESPACE="l1-troubleshooting"
CLICKHOUSE_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

if [ -z "$CLICKHOUSE_POD" ]; then
    echo "Error: ClickHouse pod not found"
    echo "Make sure ClickHouse is installed first: aws/scripts/install-clickhouse-helm.sh"
    exit 1
fi

echo "Using ClickHouse pod: $CLICKHOUSE_POD"

# Get password from Kubernetes secret
echo "Retrieving ClickHouse credentials from secret..."
CLICKHOUSE_PASSWORD=$(kubectl get secret clickhouse-credentials -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)

# Create database
echo ""
echo "Creating l1_troubleshooting database..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE DATABASE IF NOT EXISTS l1_troubleshooting
"

# Create anomalies table
echo ""
echo "Creating anomalies table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
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

# Create sessions table
echo ""
echo "Creating sessions table..."
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

# Create metrics table
echo ""
echo "Creating metrics table..."
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

# Verify tables created
echo ""
echo "Verifying database setup..."
echo "Databases:"
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "SHOW DATABASES"

echo ""
echo "Tables in l1_troubleshooting:"
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "SHOW TABLES FROM l1_troubleshooting"

echo ""
echo "✅ ClickHouse database initialization complete!"
echo ""
echo "Database: l1_troubleshooting"
echo "Tables: anomalies, sessions, metrics"
