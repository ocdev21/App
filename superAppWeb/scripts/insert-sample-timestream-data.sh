#!/bin/bash

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
DATABASE_NAME="SuperAppDB"
TABLE_NAME="UEReports"

echo "=================================================="
echo "Inserting Sample Data to Timestream"
echo "=================================================="
echo "Database: ${DATABASE_NAME}"
echo "Table: ${TABLE_NAME}"
echo "=================================================="

# Get current timestamp in milliseconds
CURRENT_TIME=$(date +%s%3N)

echo ""
echo "Inserting sample UE Reports data..."

# Insert sample records (InfluxDB-style with tags and fields)
aws timestream-write write-records \
    --database-name ${DATABASE_NAME} \
    --table-name ${TABLE_NAME} \
    --region ${AWS_REGION} \
    --records "[
        {
            \"Dimensions\": [
                {\"Name\": \"server\", \"Value\": \"ue-server-01\"},
                {\"Name\": \"region\", \"Value\": \"us-east-1\"},
                {\"Name\": \"environment\", \"Value\": \"production\"}
            ],
            \"MeasureName\": \"cpu_usage\",
            \"MeasureValue\": \"45.2\",
            \"MeasureValueType\": \"DOUBLE\",
            \"Time\": \"${CURRENT_TIME}\",
            \"TimeUnit\": \"MILLISECONDS\"
        },
        {
            \"Dimensions\": [
                {\"Name\": \"server\", \"Value\": \"ue-server-01\"},
                {\"Name\": \"region\", \"Value\": \"us-east-1\"},
                {\"Name\": \"environment\", \"Value\": \"production\"}
            ],
            \"MeasureName\": \"memory_usage\",
            \"MeasureValue\": \"2048\",
            \"MeasureValueType\": \"BIGINT\",
            \"Time\": \"${CURRENT_TIME}\",
            \"TimeUnit\": \"MILLISECONDS\"
        },
        {
            \"Dimensions\": [
                {\"Name\": \"server\", \"Value\": \"ue-server-02\"},
                {\"Name\": \"region\", \"Value\": \"us-west-2\"},
                {\"Name\": \"environment\", \"Value\": \"production\"}
            ],
            \"MeasureName\": \"cpu_usage\",
            \"MeasureValue\": \"62.8\",
            \"MeasureValueType\": \"DOUBLE\",
            \"Time\": \"${CURRENT_TIME}\",
            \"TimeUnit\": \"MILLISECONDS\"
        },
        {
            \"Dimensions\": [
                {\"Name\": \"server\", \"Value\": \"ue-server-02\"},
                {\"Name\": \"region\", \"Value\": \"us-west-2\"},
                {\"Name\": \"environment\", \"Value\": \"production\"}
            ],
            \"MeasureName\": \"memory_usage\",
            \"MeasureValue\": \"3072\",
            \"MeasureValueType\": \"BIGINT\",
            \"Time\": \"${CURRENT_TIME}\",
            \"TimeUnit\": \"MILLISECONDS\"
        }
    ]"

echo "✓ Sample data inserted successfully"

# Query the data
echo ""
echo "Querying inserted data..."
aws timestream-query query \
    --region ${AWS_REGION} \
    --query-string "SELECT * FROM \"${DATABASE_NAME}\".\"${TABLE_NAME}\" ORDER BY time DESC LIMIT 10" \
    --output table

echo ""
echo "=================================================="
echo "✓ Sample Data Insert Complete!"
echo "=================================================="
echo ""
echo "Data structure (InfluxDB-style):"
echo "  - Dimensions (tags): server, region, environment"
echo "  - Measures (fields): cpu_usage, memory_usage"
echo "  - Time: millisecond precision"
echo ""
echo "Your application can now query this data!"
echo "=================================================="
