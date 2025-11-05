#!/bin/bash

# Fix processed_files table schema - Change processing_time from UInt32 to DateTime

set -e

NAMESPACE="l1-troubleshooting"
CLICKHOUSE_PASSWORD="defaultpass"

echo "========================================="
echo "Fixing processed_files Table Schema"
echo "========================================="

# Get ClickHouse pod
echo "Finding ClickHouse pod..."
CLICKHOUSE_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

if [ -z "$CLICKHOUSE_POD" ]; then
    echo "Error: ClickHouse pod not found"
    exit 1
fi

echo "✓ Using pod: $CLICKHOUSE_POD"

# Drop the old table
echo ""
echo "Dropping old processed_files table..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
DROP TABLE IF EXISTS l1_anomaly_detection.processed_files
"
echo "✓ Old table dropped"

# Create new table with DateTime type
echo ""
echo "Creating new processed_files table with DateTime type..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
CREATE TABLE IF NOT EXISTS l1_anomaly_detection.processed_files (
    id String,
    filename String,
    file_type String,
    file_size UInt64,
    upload_date DateTime,
    processing_status String DEFAULT 'pending',
    anomalies_found UInt32 DEFAULT 0,
    processing_time Nullable(DateTime),
    error_message Nullable(String)
) ENGINE = MergeTree()
ORDER BY upload_date
"
echo "✓ New table created"

# Verify
echo ""
echo "Verifying table structure..."
kubectl exec -n $NAMESPACE $CLICKHOUSE_POD -- clickhouse-client -u default --password "$CLICKHOUSE_PASSWORD" --query "
DESCRIBE l1_anomaly_detection.processed_files
"

echo ""
echo "========================================="
echo "✅ Table Schema Fixed!"
echo "========================================="
echo ""
echo "processing_time column is now Nullable(DateTime)"
echo "You can now run the ML analyzer without errors."
