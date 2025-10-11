#!/bin/bash

# Activate Python virtual environment
source .venv/bin/activate

# Start RAG Flask server in background
echo "Starting RAG service on port 8001..."
python3 rag_server.py &
RAG_PID=$!
echo "RAG service started with PID: $RAG_PID"

# Wait for RAG server to be ready
sleep 3

# Start Express server
echo "Starting Express server..."
NODE_ENV=development tsx server/index.ts

# Cleanup on exit
trap "kill $RAG_PID 2>/dev/null" EXIT
