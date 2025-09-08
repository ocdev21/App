
#!/bin/bash

echo "Setting up ClickHouse database for L1 Application"
echo "================================================="

# Wait for the correct service name to be available
SERVICE_NAME="chi-clickhouse-single-clickhouse-0-0"
NAMESPACE="l1-app-ai"

echo "Waiting for ClickHouse service to be available..."
echo "Looking for service: $SERVICE_NAME"

# Wait up to 5 minutes for service to be created
timeout 300 bash -c "until kubectl get svc $SERVICE_NAME -n $NAMESPACE > /dev/null 2>&1; do echo 'Waiting for service...'; sleep 10; done"

if [ $? -ne 0 ]; then
    echo "❌ Service $SERVICE_NAME not found after 5 minutes"
    echo "Available services in namespace $NAMESPACE:"
    kubectl get svc -n $NAMESPACE
    echo "Available CHI resources:"
    kubectl get chi -n $NAMESPACE -o wide
    exit 1
fi

echo "✅ Service $SERVICE_NAME found"

# Test ClickHouse connection
echo "Testing ClickHouse connection..."
kubectl exec -n $NAMESPACE deployment/chi-clickhouse-single-clickhouse-0-0 -- clickhouse-client --password="defaultpass" --query "SELECT 1" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ ClickHouse is not responding"
    echo "Pod logs:"
    kubectl logs -l clickhouse.altinity.com/chi=clickhouse-single -n $NAMESPACE --tail=50
    exit 1
fi

echo "✅ ClickHouse is responding"

# Create database and tables
echo "Creating database and tables..."

kubectl exec -n $NAMESPACE deployment/chi-clickhouse-single-clickhouse-0-0 -- clickhouse-client --password="defaultpass" --query "
CREATE DATABASE IF NOT EXISTS l1_anomaly_detection;

CREATE TABLE IF NOT EXISTS l1_anomaly_detection.anomalies (
    id String,
    timestamp DateTime,
    anomaly_type String,
    description String,
    severity String,
    confidence_score Float32,
    source_file String,
    packet_number Nullable(UInt32),
    detection_algorithm String,
    ml_algorithm_details String,
    status String DEFAULT 'open'
) ENGINE = MergeTree()
ORDER BY timestamp;

CREATE TABLE IF NOT EXISTS l1_anomaly_detection.processed_files (
    id String,
    filename String,
    file_size UInt64,
    upload_date DateTime,
    processing_status String DEFAULT 'pending',
    processing_time DateTime,
    total_samples UInt32,
    anomalies_detected UInt32,
    session_id String,
    processing_time_ms Nullable(UInt32),
    error_message Nullable(String)
) ENGINE = MergeTree()
ORDER BY upload_date;

CREATE TABLE IF NOT EXISTS l1_anomaly_detection.metrics (
    id String,
    metric_name String,
    metric_value Float64,
    timestamp DateTime,
    category String,
    session_id Nullable(String),
    source_file Nullable(String)
) ENGINE = MergeTree()
ORDER BY timestamp;
"

if [ $? -eq 0 ]; then
    echo "✅ Database setup completed successfully!"
else
    echo "❌ Database setup failed"
    exit 1
fi

echo ""
echo "📊 Database Information:"
echo "   - Host: $SERVICE_NAME.$NAMESPACE.svc.cluster.local"
echo "   - HTTP Port: 8123"
echo "   - TCP Port: 9000" 
echo "   - Database: l1_anomaly_detection"
echo "   - Username: default"
echo "   - Password: defaultpass"
