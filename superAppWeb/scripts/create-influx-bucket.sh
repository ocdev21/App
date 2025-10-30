#!/bin/bash

set -e

echo "=================================================="
echo "InfluxDB - Create Bucket"
echo "=================================================="
echo ""

# Configuration
CONFIG_NAME="superAppDB"
BUCKET_NAME="${1}"

# Check if bucket name is provided
if [ -z "$BUCKET_NAME" ]; then
  echo "❌ ERROR: Bucket name is required"
  echo ""
  echo "Usage:"
  echo "  ./scripts/create-influx-bucket.sh <bucket-name>"
  echo ""
  echo "Example:"
  echo "  ./scripts/create-influx-bucket.sh MyMetrics"
  echo "  ./scripts/create-influx-bucket.sh SensorData"
  exit 1
fi

echo "Config: $CONFIG_NAME"
echo "Bucket: $BUCKET_NAME"
echo ""

# Check if influx CLI is installed
echo "Step 1: Checking InfluxDB CLI..."
if ! command -v influx &> /dev/null; then
  echo "❌ ERROR: influx CLI not found"
  echo ""
  echo "Install InfluxDB CLI:"
  echo "  https://docs.influxdata.com/influxdb/v2/tools/influx-cli/"
  exit 1
fi

echo "✓ InfluxDB CLI found"

# Check if config exists
echo ""
echo "Step 2: Verifying config '$CONFIG_NAME'..."
influx config list | grep -q "$CONFIG_NAME" || {
  echo "❌ ERROR: Config '$CONFIG_NAME' not found"
  echo ""
  echo "Available configs:"
  influx config list
  echo ""
  echo "Create config with:"
  echo "  influx config create --config-name $CONFIG_NAME --host-url <influx-url> --token <your-token> --org <your-org>"
  exit 1
}

echo "✓ Config '$CONFIG_NAME' exists"

# Check if bucket already exists
echo ""
echo "Step 3: Checking if bucket exists..."
BUCKET_EXISTS=$(influx bucket list -c "$CONFIG_NAME" --name "$BUCKET_NAME" --json 2>/dev/null | grep -c "\"name\":\"$BUCKET_NAME\"" || echo "0")

if [ "$BUCKET_EXISTS" != "0" ]; then
  echo "⚠️  Bucket '$BUCKET_NAME' already exists"
  echo ""
  echo "Bucket details:"
  influx bucket list -c "$CONFIG_NAME" --name "$BUCKET_NAME"
  exit 0
fi

# Create bucket
echo ""
echo "Step 4: Creating bucket '$BUCKET_NAME'..."

influx bucket create --name "$BUCKET_NAME" -c "$CONFIG_NAME"

echo "✓ Bucket created successfully"

# Verify bucket creation
echo ""
echo "Step 5: Verifying bucket..."
influx bucket list -c "$CONFIG_NAME" --name "$BUCKET_NAME"

echo ""
echo "=================================================="
echo "✓ SUCCESS! Bucket created"
echo "=================================================="
echo ""
echo "Bucket: $BUCKET_NAME"
echo "Config: $CONFIG_NAME"
echo ""
echo "Write data to this bucket:"
echo "  influx write -c $CONFIG_NAME -b $BUCKET_NAME 'measurement,tag=value field=123'"
echo ""
echo "Query this bucket:"
echo "  influx query -c $CONFIG_NAME 'from(bucket: \"$BUCKET_NAME\") |> range(start: -1h)'"
