
#!/bin/bash

echo "Setting up ClickHouse database for L1 Application"
echo "================================================"

# Wait for ClickHouse to be ready
echo "Waiting for ClickHouse service to be available..."
kubectl wait --for=condition=ready pod -l clickhouse.altinity.com/chi=ch-ai -n l1-app-ai --timeout=300s

# Get the ClickHouse service name
CH_SERVICE="chi-ch-ai-ch-cluster-0-0"
CH_NAMESPACE="l1-app-ai"

echo "Creating database and tables..."

# Create database
kubectl exec -n $CH_NAMESPACE svc/$CH_SERVICE -- clickhouse-client --query="CREATE DATABASE IF NOT EXISTS l1_anomaly_detection"

# Create anomalies table
kubectl exec -n $CH_NAMESPACE svc/$CH_SERVICE -- clickhouse-client --query="
CREATE TABLE IF NOT EXISTS l1_anomaly_detection.anomalies (
    id String,
    timestamp DateTime,
    anomaly_type String,
    description String,
    severity String,
    source_file String,
    packet_number UInt32,
    line_number UInt32,
    session_id String,
    confidence_score Float64,
    model_agreement UInt8,
    ml_algorithm_details String,
    isolation_forest_score Float64,
    one_class_svm_score Float64,
    dbscan_prediction Int8,
    random_forest_score Float64,
    ensemble_vote String,
    detection_timestamp String,
    status String,
    ecpri_message_type String,
    ecpri_sequence_number UInt32,
    fronthaul_latency_us Float64,
    timing_jitter_us Float64,
    bandwidth_utilization Float64,
    file_size UInt64,
    upload_date DateTime,
    processing_status String DEFAULT 'pending',
    processing_time DateTime,
    total_samples UInt32,
    anomalies_detected UInt32,
    anomalies_found UInt32 DEFAULT 0,
    processing_time_ms Nullable(UInt32),
    error_message Nullable(String)
) ENGINE = MergeTree()
ORDER BY upload_date"

# Create metrics table
kubectl exec -n $CH_NAMESPACE svc/$CH_SERVICE -- clickhouse-client --query="
CREATE TABLE IF NOT EXISTS l1_anomaly_detection.metrics (
    id String,
    metric_name String,
    metric_value Float64,
    timestamp DateTime,
    category String,
    session_id Nullable(String),
    source_file Nullable(String)
) ENGINE = MergeTree()
ORDER BY timestamp"

echo "✅ Database setup completed!"
echo ""
echo "📊 Database Access Information:"
echo "   - Service: chi-ch-ai-ch-cluster-0-0.l1-app-ai.svc.cluster.local"
echo "   - HTTP Port: 8123"
echo "   - Native Port: 9000"
echo "   - Database: l1_anomaly_detection"
echo "   - Username: default"
echo "   - Password: (empty)"
echo ""
echo "🔍 To verify installation:"
echo "   kubectl get chi -n l1-app-ai"
echo "   kubectl get pods -n l1-app-ai"
echo "   kubectl logs -l clickhouse.altinity.com/chi=ch-ai -n l1-app-ai"
