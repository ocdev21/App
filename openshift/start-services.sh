#!/bin/bash

echo "=========================================="
echo "Starting L1 Integrated Services"
echo "=========================================="
echo ""

# Function to handle graceful shutdown
cleanup() {
    echo ""
    echo "Shutting down services..."
    kill $RAG_PID $APP_PID 2>/dev/null
    if [ -n "$AI_PID" ]; then kill $AI_PID 2>/dev/null; fi
    wait $RAG_PID $APP_PID 2>/dev/null
    if [ -n "$AI_PID" ]; then wait $AI_PID 2>/dev/null; fi
    echo "Services stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start RAG Service in background
echo "[1/3] Starting RAG Service (port 8001)..."
python3 /app/rag_server.py &
RAG_PID=$!
echo "  RAG Service PID: $RAG_PID"

# Wait for RAG service to initialize
echo "  Waiting for RAG service to initialize ChromaDB..."
sleep 3

# Check if RAG service is running
if ! kill -0 $RAG_PID 2>/dev/null; then
    echo "ERROR: RAG Service failed to start!"
    exit 1
fi

echo "  RAG Service initialized successfully"
echo ""

# Check if GGUF model exists in embedded storage
MODEL_PATH="/app/models/mistral.gguf"
AI_PID=""
echo "Checking for GGUF model..."
if [ ! -f "$MODEL_PATH" ]; then
    echo "=========================================="
    echo "WARNING: GGUF Model Not Found!"
    echo "=========================================="
    echo ""
    echo "The Mistral model is not present at: $MODEL_PATH"
    echo ""
    echo "AI Inference service will NOT start."
    echo "Web application will start in limited mode."
    echo ""
    echo "To enable AI recommendations:"
    echo "  The model should be embedded in the Docker image during build."
    echo "  See BUILD_INSTRUCTIONS.md for build steps with model inclusion."
    echo ""
    echo "=========================================="
    echo ""
else
    MODEL_SIZE=$(du -h "$MODEL_PATH" | cut -f1)
    echo "  Model found: $MODEL_SIZE at $MODEL_PATH"
    echo ""

    # Start AI Inference Server in background
    echo "[2/3] Starting AI Inference Server (port 8000)..."
    python3 /app/gguf-server.py &
    AI_PID=$!
    echo "  AI Server PID: $AI_PID"

    # Wait for AI server to initialize
    echo "  Waiting for AI server to load model..."
    sleep 5

    # Check if AI server is running
    if ! kill -0 $AI_PID 2>/dev/null; then
        echo "ERROR: AI Inference Server failed to start!"
        kill $RAG_PID 2>/dev/null
        exit 1
    fi

    echo "  AI Server initialized successfully"
    echo ""
fi

# Start L1 Application (frontend + backend)
echo "[3/3] Starting L1 Web Application (port 5000)..."
cd /app
npm run dev &
APP_PID=$!
echo "  L1 App PID: $APP_PID"
echo ""

echo "=========================================="
echo "Services Running:"
echo "  - L1 Web App:     http://0.0.0.0:5000"
echo "  - RAG Service:    http://0.0.0.0:8001"
if [ -n "$AI_PID" ]; then
    echo "  - AI Inference:   http://0.0.0.0:8000"
else
    echo "  - AI Inference:   DISABLED (model not found)"
fi
echo "=========================================="
echo ""
echo "Monitoring services (Ctrl+C to stop)..."

# Monitor all processes
while true; do
    # Check RAG service
    if ! kill -0 $RAG_PID 2>/dev/null; then
        echo "ERROR: RAG Service stopped unexpectedly!"
        if [ -n "$AI_PID" ]; then kill $AI_PID 2>/dev/null; fi
        kill $APP_PID 2>/dev/null
        exit 1
    fi
    
    # Check AI server (only if it was started)
    if [ -n "$AI_PID" ]; then
        if ! kill -0 $AI_PID 2>/dev/null; then
            echo "ERROR: AI Inference Server stopped unexpectedly!"
            kill $RAG_PID $APP_PID 2>/dev/null
            exit 1
        fi
    fi
    
    # Check L1 app
    if ! kill -0 $APP_PID 2>/dev/null; then
        echo "ERROR: L1 Application stopped unexpectedly!"
        kill $RAG_PID 2>/dev/null
        if [ -n "$AI_PID" ]; then kill $AI_PID 2>/dev/null; fi
        exit 1
    fi
    
    sleep 5
done
