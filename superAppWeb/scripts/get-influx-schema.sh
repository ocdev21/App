#!/bin/bash

set -e

echo "=================================================="
echo "InfluxDB - Get Buckets and Schema"
echo "=================================================="
echo ""

# Configuration
VM_HOST="${VM_HOST:-localhost}"
VM_USER="${VM_USER:-$USER}"
VM_PORT="${VM_PORT:-22}"
CONFIG_NAME="superAppDB"
USE_SSH="${USE_SSH:-false}"

echo "Configuration:"
echo "  VM Host: $VM_HOST"
echo "  VM User: $VM_USER"
echo "  VM Port: $VM_PORT"
echo "  Config: $CONFIG_NAME"
echo "  Use SSH: $USE_SSH"
echo ""

# Function to run influx command (local or via SSH)
run_influx_cmd() {
  local cmd="$1"
  if [ "$USE_SSH" = "true" ]; then
    ssh -p "$VM_PORT" "$VM_USER@$VM_HOST" "$cmd"
  else
    eval "$cmd"
  fi
}

# Check if influx CLI is available
echo "Step 1: Checking InfluxDB CLI..."
if [ "$USE_SSH" = "true" ]; then
  echo "Checking on remote VM: $VM_HOST"
  if ! ssh -p "$VM_PORT" "$VM_USER@$VM_HOST" "command -v influx" &> /dev/null; then
    echo "❌ ERROR: influx CLI not found on remote VM"
    exit 1
  fi
else
  if ! command -v influx &> /dev/null; then
    echo "❌ ERROR: influx CLI not found locally"
    echo ""
    echo "Install InfluxDB CLI:"
    echo "  https://docs.influxdata.com/influxdb/v2/tools/influx-cli/"
    exit 1
  fi
fi

echo "✓ InfluxDB CLI found"

# List all buckets
echo ""
echo "Step 2: Listing all buckets..."
echo ""

BUCKETS=$(run_influx_cmd "influx bucket list -c $CONFIG_NAME --json")

if [ -z "$BUCKETS" ] || [ "$BUCKETS" = "null" ]; then
  echo "❌ No buckets found or error connecting"
  echo ""
  echo "Check your config with:"
  echo "  influx config list"
  exit 1
fi

echo "$BUCKETS" | jq -r '.[] | "  • \(.name) (ID: \(.id), Retention: \(.retentionRules[0].everySeconds // "infinite") seconds)"'

# Get bucket names
BUCKET_NAMES=$(echo "$BUCKETS" | jq -r '.[].name')

# For each bucket, get schema
echo ""
echo "Step 3: Getting schema for each bucket..."
echo ""

for BUCKET in $BUCKET_NAMES; do
  echo "=================================================="
  echo "Bucket: $BUCKET"
  echo "=================================================="
  echo ""
  
  # Get measurements (unique measurement names)
  echo "Measurements:"
  MEASUREMENTS=$(run_influx_cmd "influx query -c $CONFIG_NAME \"
    import \\\"influxdata/influxdb/schema\\\"
    schema.measurements(bucket: \\\"$BUCKET\\\")
  \"" 2>/dev/null || echo "")
  
  if [ -z "$MEASUREMENTS" ]; then
    echo "  No measurements found (bucket may be empty)"
  else
    echo "$MEASUREMENTS" | grep -v "^$" | grep -v "Result:" | grep -v "Table:" | awk '{print "  • " $0}'
  fi
  
  echo ""
  
  # Get field keys and tag keys for each measurement
  echo "Schema Details:"
  
  # Try to get field keys
  FIELDS=$(run_influx_cmd "influx query -c $CONFIG_NAME \"
    import \\\"influxdata/influxdb/schema\\\"
    schema.fieldKeys(bucket: \\\"$BUCKET\\\")
  \"" 2>/dev/null || echo "")
  
  if [ ! -z "$FIELDS" ]; then
    echo "  Fields:"
    echo "$FIELDS" | grep -v "^$" | grep -v "Result:" | grep -v "Table:" | awk '{print "    - " $0}'
  fi
  
  echo ""
  
  # Try to get tag keys
  TAGS=$(run_influx_cmd "influx query -c $CONFIG_NAME \"
    import \\\"influxdata/influxdb/schema\\\"
    schema.tagKeys(bucket: \\\"$BUCKET\\\")
  \"" 2>/dev/null || echo "")
  
  if [ ! -z "$TAGS" ]; then
    echo "  Tags:"
    echo "$TAGS" | grep -v "^$" | grep -v "Result:" | grep -v "Table:" | awk '{print "    - " $0}'
  fi
  
  echo ""
  echo "---"
  echo ""
done

echo ""
echo "=================================================="
echo "✓ Complete!"
echo "=================================================="
echo ""
echo "Summary:"
echo "  Total buckets: $(echo "$BUCKET_NAMES" | wc -l)"
echo ""
echo "To query a specific bucket:"
echo "  influx query -c $CONFIG_NAME 'from(bucket: \"<bucket-name>\") |> range(start: -1h) |> limit(n: 10)'"
