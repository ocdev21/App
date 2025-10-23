-- Add packet_context column to anomalies table in ClickHouse
-- This column stores the anomaly packet plus 2 packets before and 2 after for context

USE l1_anomaly_detection;

-- Add the new column to the anomalies table
ALTER TABLE anomalies ADD COLUMN IF NOT EXISTS packet_context String DEFAULT '';

-- Verify the column was added
DESCRIBE TABLE anomalies;
