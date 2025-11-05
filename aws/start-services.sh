#!/bin/bash

echo "=========================================="
echo "Starting L1 Integrated Services"
echo "=========================================="
echo ""

# Function to handle graceful shutdown
cleanup() {
    echo ""
    echo "Shutting down services..."
    kill $AI_PID $APP_PID 2>/dev/null
    wait $AI_PID $APP_PID 2>/dev/null
    echo "Services stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start AI Inference Server in background
echo "[1/2] Starting AI Inference Server (Amazon Bedrock - port 8000)..."
python3 /app/bedrock-server.py &
AI_PID=$!
echo "  AI Server PID: $AI_PID"

# Wait for AI server to initialize (Bedrock is much faster than local models)
echo "  Waiting for AI server to initialize..."
sleep 2

# Check if AI server is running
if ! kill -0 $AI_PID 2>/dev/null; then
    echo "ERROR: AI Inference Server failed to start!"
    exit 1
fi

echo "  AI Server initialized successfully"
echo ""

# Start L1 Application (frontend + backend) in production mode
echo "[2/2] Starting L1 Web Application (port 5000)..."
cd /app
NODE_ENV=production npx tsx server/index.ts &
APP_PID=$!
echo "  L1 App PID: $APP_PID"
echo ""

echo "=========================================="
echo "Services Running:"
echo "  - L1 Web App:     http://0.0.0.0:5000"
echo "  - AI Inference:   http://0.0.0.0:8000 (Amazon Bedrock Nova Pro)"
echo "=========================================="
echo ""
echo "Monitoring services (Ctrl+C to stop)..."

# Monitor both processes
while true; do
    # Check AI server
    if ! kill -0 $AI_PID 2>/dev/null; then
        echo "ERROR: AI Inference Server stopped unexpectedly!"
        kill $APP_PID 2>/dev/null
        exit 1
    fi
    
    # Check L1 app
    if ! kill -0 $APP_PID 2>/dev/null; then
        echo "ERROR: L1 Application stopped unexpectedly!"
        kill $AI_PID 2>/dev/null
        exit 1
    fi
    
    sleep 5
done
