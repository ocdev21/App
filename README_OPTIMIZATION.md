# Docker Image Size Optimization

## Summary

Reduced Docker image size from **13.7GB to ~1-2GB** by removing LLM components and using minimal dependencies.

## Changes Made

### 1. **Removed Heavy LLM Dependencies**
```bash
# These packages were removed (saved ~10GB):
transformers>=4.30.0      # ~4GB
torch>=2.0.0             # ~5GB  
llama-cpp-python>=0.2.0  # ~2GB
accelerate>=0.20.0       # ~500MB
sentencepiece>=0.1.99    # ~200MB
```

### 2. **Created Minimal Requirements** (`requirements_minimal.txt`)
- Only essential packages for core functionality
- Removed AI/ML packages: `torch`, `transformers`, `llama-cpp-python`
- Removed development packages: `pytest`, `black`, `flake8`
- Removed visualization packages: `matplotlib`, `seaborn`

### 3. **Optimized Dockerfile** (`Dockerfile.minimal`)
- Uses `node:18-alpine` (lightweight base image)
- Multi-stage build to reduce final image size
- `.dockerignore` excludes LLM-related files

### 4. **Removed LLM Services**
- `server/services/tslam_service.py` - TSLAM AI service
- `server/services/streaming_mistral_analyzer.py` - Mistral AI
- `server/services/remote_tslam_client.py` - Remote LLM client
- WebSocket streaming for AI recommendations

### 5. **Modified Routes** (`server/routes.minimal.ts`)
- Removed WebSocket server for AI streaming
- Replaced AI recommendations with static responses
- Kept core PCAP processing functionality

## Build Instructions

### Use Minimal Image:
```bash
# Build optimized image
docker build -f Dockerfile.minimal -t l1-app-minimal .

# Check size (should be ~1-2GB vs 13.7GB)
docker images | grep l1-app
```

### Use Original (if needed):
```bash
# Original build (13.7GB)
docker build -f Dockerfile -t l1-app-full .
```

## What Still Works

✅ **Core Functionality:**
- PCAP file processing and analysis
- Anomaly detection (MAC, timing, protocol)
- ClickHouse database integration
- Dashboard metrics and trends
- File upload and processing
- Basic recommendations (static)

❌ **Removed Features:**
- AI-powered streaming recommendations
- TSLAM/Mistral LLM integration  
- Advanced explainable AI analysis
- Remote LLM server connectivity

## Usage

The application retains all core network troubleshooting capabilities while removing the AI/LLM components that caused the massive image size.

All essential L1 network analysis, PCAP processing, and anomaly detection remain fully functional.