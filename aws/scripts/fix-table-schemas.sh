#!/bin/bash

# Fix table schemas to match folder_anomaly_analyzer_clickhouse.py expectations

set -e

NAMESPACE="l1-troubleshooting"
CLICKHOUSE_PASSWORD="defaultpass"

echo "========================================="
echo "Fixing Table Schemas"
echo "========================================="

# Get ClickHouse pod
echo "Finding ClickHouse pod..."
CLICKHOUSE_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

if [ -z "$CLICKHOUSE_POD" ]; then
    echo "Error: ClickHouse pod not found"
    exit 1
fi

echo "✓ Using pod: $CLICKHOUSE_POD"

# Fix sessions table - add 'id' column
echo ""
echo "Fixing sessions table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
DROP TABLE IF EXISTS l1_anomaly_detection.sessions
"

kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE TABLE l1_anomaly_detection.sessions (
    id UInt64,
    session_name String,
    folder_path String,
    total_files UInt32,
    pcap_files UInt32,
    text_files UInt32,
    total_anomalies UInt32,
    start_time DateTime,
    end_time DateTime,
    duration_seconds UInt32,
    status String
) ENGINE = MergeTree()
ORDER BY (start_time, id)
"
echo "✓ Sessions table fixed"

# Fix anomalies table - add file_path, file_type, packet_context columns
echo ""
echo "Fixing anomalies table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
DROP TABLE IF EXISTS l1_anomaly_detection.anomalies
"

kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE TABLE l1_anomaly_detection.anomalies (
    id UInt64,
    file_path String,
    file_type String,
    packet_number UInt32,
    anomaly_type String,
    severity String,
    description String,
    details String,
    ue_id String,
    du_mac String,
    ru_mac String,
    timestamp DateTime,
    status String,
    error_log String DEFAULT '',
    packet_context String DEFAULT ''
) ENGINE = MergeTree()
ORDER BY (timestamp, severity, anomaly_type)
PARTITION BY toYYYYMM(timestamp)
"
echo "✓ Anomalies table fixed"

# Verify schemas
echo ""
echo "Verifying schemas..."
echo ""
echo "Sessions table:"
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
DESCRIBE l1_anomaly_detection.sessions
"

echo ""
echo "Anomalies table:"
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
DESCRIBE l1_anomaly_detection.anomalies
"

echo ""
echo "========================================="
echo "✅ Table Schemas Fixed!"
echo "========================================="
echo ""
echo "You can now run the ML analyzer without schema errors."
