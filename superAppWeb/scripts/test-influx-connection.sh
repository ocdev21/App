#!/bin/bash

set -e

echo "=================================================="
echo "Test InfluxDB Connection from Python"
echo "=================================================="
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
  echo "❌ ERROR: python3 not found"
  exit 1
fi

echo "Python version: $(python3 --version)"
echo ""

# Check if influxdb-client is installed
echo "Checking for influxdb-client package..."
if ! python3 -c "import influxdb_client" 2>/dev/null; then
  echo "⚠️  influxdb-client not installed"
  echo ""
  echo "Installing influxdb-client..."
  pip3 install influxdb-client aiohttp ciso8601
  echo ""
fi

echo "✓ influxdb-client installed"
echo ""

# Check environment variables
echo "Checking environment variables..."
MISSING_VARS=()

if [ -z "$INFLUXDB_URL" ] && [ -z "$INFLUXDB_V2_URL" ]; then
  MISSING_VARS+=("INFLUXDB_URL or INFLUXDB_V2_URL")
fi

if [ -z "$INFLUXDB_TOKEN" ] && [ -z "$INFLUXDB_V2_TOKEN" ]; then
  MISSING_VARS+=("INFLUXDB_TOKEN or INFLUXDB_V2_TOKEN")
fi

if [ -z "$INFLUXDB_ORG" ] && [ -z "$INFLUXDB_V2_ORG" ]; then
  MISSING_VARS+=("INFLUXDB_ORG or INFLUXDB_V2_ORG")
fi

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "❌ Missing required environment variables:"
  for var in "${MISSING_VARS[@]}"; do
    echo "   - $var"
  done
  echo ""
  echo "Set them with:"
  echo "  export INFLUXDB_URL=\"http://your-influxdb:8086\""
  echo "  export INFLUXDB_TOKEN=\"your-token\""
  echo "  export INFLUXDB_ORG=\"your-org\""
  echo "  export INFLUXDB_BUCKET=\"superAppDB\"  # optional"
  exit 1
fi

echo "✓ Environment variables configured"
echo ""
echo "Configuration:"
echo "  URL: ${INFLUXDB_URL:-${INFLUXDB_V2_URL}}"
echo "  Org: ${INFLUXDB_ORG:-${INFLUXDB_V2_ORG}}"
echo "  Bucket: ${INFLUXDB_BUCKET:-superAppDB}"
echo "  Token: ****${INFLUXDB_TOKEN: -4}"
echo ""

# Run the test
echo "Running connection test..."
echo ""

python3 shared/influxdb_client.py

echo ""
echo "=================================================="
echo "✓ Test Complete!"
echo "=================================================="
