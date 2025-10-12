# L1 Integrated - Quick Start Guide

**TL;DR: Build → Deploy → Copy PCAPs → Monitor**

---

## 🚀 One-Command Build

```bash
cd openshift
chmod +x build-embedded.sh
./build-embedded.sh
```

**Done!** Image built with embedded model (~10GB) and pushed to registry.

---

## 📦 Deploy to OpenShift

```bash
# Login and switch to namespace
oc login <cluster-url>
oc project l1-app-ai

# Clean up old resources
oc delete pod l1-integrated -n l1-app-ai --force --grace-period=0 --ignore-not-found=true
oc delete pvc l1-app-ai-model-pvc l1-model-storage -n l1-app-ai --ignore-not-found=true

# Deploy (no PVC needed!)
oc apply -f openshift/l1-pod-embedded.yaml

# Monitor startup
oc logs -f l1-integrated -n l1-app-ai
```

---

## 📂 Copy PCAP Files

### Single File
```bash
oc cp /path/to/sample.pcap l1-app-ai/l1-integrated:/app/ml_data/input_files/sample.pcap
```

### Multiple Files
```bash
# From local directory
for file in /path/to/pcaps/*.pcap; do
  oc cp "$file" l1-app-ai/l1-integrated:/app/ml_data/input_files/$(basename "$file")
done
```

### Verify Files Copied
```bash
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/ml_data/input_files/
```

---

## 🔍 Monitor & Verify

### Check Services
```bash
# Pod status
oc get pods -n l1-app-ai

# Service health
oc exec l1-integrated -n l1-app-ai -- curl -s http://localhost:8000/health
oc exec l1-integrated -n l1-app-ai -- curl -s http://localhost:8001/health

# Model verification
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/models/mistral.gguf
```

### Monitor ML Processing
```bash
# Watch ML analysis logs
oc logs -f l1-integrated -n l1-app-ai | grep --line-buffered -i "processing\|anomaly"

# Check generated ML models
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/ml_data/models/
```

### Access Application
```bash
# Get public URL
oc get route l1-integrated-route -n l1-app-ai -o jsonpath='{.spec.host}'

# Open in browser
echo "https://$(oc get route l1-integrated-route -n l1-app-ai -o jsonpath='{.spec.host}')"
```

---

## 🛠️ Common Operations

### Update Model (Rebuild)
```bash
cd openshift
./build-embedded.sh
oc delete pod l1-integrated -n l1-app-ai --force --grace-period=0
oc apply -f l1-pod-embedded.yaml
```

### Re-copy PCAPs After Pod Restart
```bash
# PCAPs are ephemeral - re-copy after restart
for file in /local/pcaps/*.pcap; do
  oc cp "$file" l1-app-ai/l1-integrated:/app/ml_data/input_files/$(basename "$file")
done
```

### Debugging
```bash
# Full logs
oc logs l1-integrated -n l1-app-ai

# Live tail
oc logs -f l1-integrated -n l1-app-ai

# Shell access
oc exec -it l1-integrated -n l1-app-ai -- /bin/bash

# Check all services
oc exec l1-integrated -n l1-app-ai -- ps aux | grep -E "python|node|tsx"
```

---

## 📋 Architecture Quick Reference

### Ports
- **5000**: L1 Web Application (frontend + backend)
- **8000**: AI Inference Server (Mistral-7B GGUF)
- **8001**: RAG Service (ChromaDB + embeddings)

### Storage Paths
- **Model**: `/app/models/mistral.gguf` (embedded, 4.1GB)
- **PCAP Input**: `/app/ml_data/input_files/` (ephemeral)
- **ML Models**: `/app/ml_data/models/` (ephemeral, PKL files)
- **ChromaDB**: `/app/chromadb/` (ephemeral)
- **Uploaded Docs**: `/app/uploaded_docs/` (ephemeral)

### Environment Variables
```bash
# Set in l1-pod-embedded.yaml
NODE_ENV=production
PORT=5000
PYTHONUNBUFFERED=1
PYTHONDONTWRITEBYTECODE=1
TSLAM_REMOTE_HOST=localhost
TSLAM_REMOTE_PORT=5000
ML_MODELS_DIR=/app/models
INPUT_FILES_DIR=/app/ml_data/input_files
FEATURE_HISTORY_DIR=/app/ml_data/feature_history
RETRAIN_THRESHOLD=10
CHROMADB_PERSIST_DIR=/app/chromadb
RAG_SERVICE_URL=http://localhost:8001
UPLOADED_DOCS_DIR=/app/uploaded_docs
```

---

## ⚠️ Important Notes

1. **No PVC Required**: Embedded model eliminates storage dependencies
2. **Ephemeral Data**: PCAP files, ChromaDB, uploaded docs reset on pod restart
3. **Database Persistence**: All anomaly data in PostgreSQL/ClickHouse persists
4. **Image Size**: ~10GB (includes 4.1GB model)
5. **Build Time**: 5-10 minutes with embedded model

---

**For detailed instructions, see:** [`BUILD_INSTRUCTIONS_EMBEDDED.md`](BUILD_INSTRUCTIONS_EMBEDDED.md)
