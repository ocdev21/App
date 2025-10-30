#!/bin/bash

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
DATABASE_NAME="SuperAppDB"
TABLE_NAME="UEReports"

echo "=================================================="
echo "Creating Timestream Database and Table"
echo "=================================================="
echo "Region: ${AWS_REGION}"
echo "Database: ${DATABASE_NAME}"
echo "Table: ${TABLE_NAME}"
echo "=================================================="

# Step 1: Create Timestream Database
echo ""
echo "Step 1: Creating Timestream database..."
if aws timestream-write describe-database \
    --database-name ${DATABASE_NAME} \
    --region ${AWS_REGION} 2>/dev/null; then
    echo "✓ Database ${DATABASE_NAME} already exists"
else
    echo "Creating database ${DATABASE_NAME}..."
    aws timestream-write create-database \
        --database-name ${DATABASE_NAME} \
        --region ${AWS_REGION} \
        --tags Key=Environment,Value=Production Key=Application,Value=SuperApp
    echo "✓ Database created successfully"
fi

# Step 2: Create UEReports Table (InfluxDB-style retention)
echo ""
echo "Step 2: Creating Timestream table with InfluxDB-style retention..."
if aws timestream-write describe-table \
    --database-name ${DATABASE_NAME} \
    --table-name ${TABLE_NAME} \
    --region ${AWS_REGION} 2>/dev/null; then
    echo "✓ Table ${TABLE_NAME} already exists"
else
    echo "Creating table ${TABLE_NAME}..."
    # InfluxDB-style retention:
    # - Memory store: 24 hours (hot data, fast queries)
    # - Magnetic store: 30 days (cold data, cost-effective)
    aws timestream-write create-table \
        --database-name ${DATABASE_NAME} \
        --table-name ${TABLE_NAME} \
        --retention-properties "MemoryStoreRetentionPeriodInHours=24,MagneticStoreRetentionPeriodInDays=30" \
        --region ${AWS_REGION} \
        --tags Key=Environment,Value=Production Key=Application,Value=SuperApp Key=Type,Value=TimeSeries
    echo "✓ Table created successfully"
fi

# Step 3: Display Table Details
echo ""
echo "Step 3: Retrieving table details..."
aws timestream-write describe-table \
    --database-name ${DATABASE_NAME} \
    --table-name ${TABLE_NAME} \
    --region ${AWS_REGION} \
    --query 'Table.{Name:TableName,Status:TableStatus,MemoryRetention:RetentionProperties.MemoryStoreRetentionPeriodInHours,MagneticRetention:RetentionProperties.MagneticStoreRetentionPeriodInDays}' \
    --output table

echo ""
echo "=================================================="
echo "✓ Timestream Setup Complete!"
echo "=================================================="
echo ""
echo "Database: ${DATABASE_NAME}"
echo "Table: ${TABLE_NAME}"
echo "Retention Policy (InfluxDB-style):"
echo "  - Memory Store: 24 hours (hot data)"
echo "  - Magnetic Store: 30 days (cold data)"
echo ""
echo "Next steps:"
echo "1. Insert sample data (optional):"
echo "   aws timestream-write write-records --database-name ${DATABASE_NAME} --table-name ${TABLE_NAME} --records ..."
echo ""
echo "2. Query your data:"
echo "   aws timestream-query query --query-string 'SELECT * FROM \"${DATABASE_NAME}\".\"${TABLE_NAME}\" LIMIT 10'"
echo ""
echo "3. Your application will automatically use this database"
echo "=================================================="
