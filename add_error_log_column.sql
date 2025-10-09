-- SQL Query to Add error_log Column to Anomalies Table
-- This column will store the actual packet data or UE event log content

-- For ClickHouse database:
ALTER TABLE l1_anomaly_detection.anomalies 
ADD COLUMN IF NOT EXISTS error_log String DEFAULT '';

-- Alternatively, for PostgreSQL (if using):
-- ALTER TABLE anomalies 
-- ADD COLUMN IF NOT EXISTS error_log TEXT DEFAULT '';

-- Verify the column was added:
-- SELECT * FROM l1_anomaly_detection.anomalies LIMIT 1;
