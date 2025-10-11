# L1 Integrated Container - Build & Deploy Instructions

## 📦 What's Included

The container includes **3 integrated services**:

1. **L1 Web Application** (Port 5000)
   - React frontend + Express backend
   - Anomaly detection dashboard
   - Knowledge Base UI

2. **RAG Service** (Port 8001)
   - ChromaDB vector database
   - Sentence transformers embeddings
   - Flask API for semantic search

3. **AI Inference Server** (Port 8000)
   - Mistral-7B GGUF model
   - CTransformers runtime
   - Streaming AI recommendations

---

## 🏗️ Build From Scratch (No Cache)

### Prerequisites
- Mistral GGUF model at: `/home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf`
- Podman or Docker installed
- Private registry access: `10.0.1.224:5000`

### Step 1: Clean Build
```bash
cd openshift

# Option A: Use the build script
./build-tslam-container.sh

# Option B: Manual build (no cache)
podman build --no-cache \
  -t 10.0.1.224:5000/l1-integrated:latest \
  -f Dockerfile.tslam .

# Push to registry
podman push 10.0.1.224:5000/l1-integrated:latest
```

### Step 2: Verify Image
```bash
# Check image size (expect ~6-8GB due to GGUF model)
podman images | grep l1-integrated

# Inspect layers
podman inspect 10.0.1.224:5000/l1-integrated:latest
```

---

## 🚀 Deploy to OpenShift

### Step 1: Setup PVC (Fresh)
```bash
# Login to OpenShift
oc login <cluster-url>
oc project l1-app-ai

# Delete old PVC for fresh start
oc delete pvc l1-ml-data-pvc --ignore-not-found=true

# Create new PVC
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: l1-ml-data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF
```

### Step 2: Deploy Pod
```bash
# Deploy the integrated pod
oc apply -f tslam-pod-with-pvc.yaml

# Monitor initialization
oc logs -f l1-integrated -c init-pvc
```

### Step 3: Verify Services
```bash
# Check pod status
oc get pods -l app=l1-integrated

# View service logs
oc logs -f l1-integrated

# Check PVC directories
POD_NAME=$(oc get pods -l app=l1-integrated -o jsonpath='{.items[0].metadata.name}')
oc exec $POD_NAME -- ls -la /pvc/
```

### Step 4: Access Application
```bash
# Get the public URL
oc get route l1-integrated -o jsonpath='{.spec.host}'

# Test endpoints
curl http://<route-url>/api/rag/stats
curl http://<route-url>/api/dashboard/metrics
```

---

## 📋 Updated Components

### Dockerfile.tslam Changes
✅ Added RAG dependencies:
```dockerfile
RUN pip install --no-cache-dir \
    chromadb \
    sentence-transformers \
    flask-cors \
    PyPDF2
```

✅ Exposed RAG port:
```dockerfile
EXPOSE 5000 8000 8001
```

### start-services.sh Changes
✅ Added RAG service startup:
```bash
[1/3] Starting RAG Service (port 8001)...
[2/3] Starting AI Inference Server (port 8000)...
[3/3] Starting L1 Web Application (port 5000)...
```

---

## 🔧 Environment Variables

The container automatically configures:
- `CHROMADB_PERSIST_DIR=/pvc/chromadb`
- `UPLOADED_DOCS_DIR=/pvc/uploaded_docs`
- `MODEL_DIR=/pvc/models`
- `INPUT_FILES_DIR=/pvc/input_files`
- `FEATURE_HISTORY_DIR=/pvc/feature_history`

---

## 📊 Service Startup Sequence

1. **RAG Service** (3 sec wait)
   - Initializes ChromaDB
   - Loads sentence-transformer model
   - Starts Flask on port 8001

2. **AI Inference Server** (5 sec wait)
   - Loads Mistral-7B GGUF model (~4GB)
   - Initializes CTransformers
   - Starts inference API on port 8000

3. **L1 Web Application**
   - Builds frontend (Vite)
   - Starts Express backend
   - Serves UI on port 5000

---

## 🧪 Testing After Deployment

```bash
# Test RAG service
curl http://<route-url>/api/rag/stats

# Test AI inference
curl -X POST http://<route-url>/api/ai/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Test","max_tokens":50}'

# Test file upload
curl -X POST http://<route-url>/api/rag/upload-file \
  -F "file=@test.pdf"
```

---

## 🔄 Rebuild & Redeploy (No Cache)

```bash
# Complete rebuild
cd openshift

# Build without cache
podman build --no-cache \
  -t 10.0.1.224:5000/l1-integrated:latest \
  -f Dockerfile.tslam .

# Push
podman push 10.0.1.224:5000/l1-integrated:latest

# Force pod restart
oc delete pod -l app=l1-integrated --force --grace-period=0

# Verify new deployment
oc logs -f l1-integrated
```

---

## 📦 PVC Directory Structure

After initialization:
```
/pvc/
├── models/              # ML model files (.pkl)
├── input_files/         # PCAP files for analysis
├── feature_history/     # Accumulated features
├── chromadb/           # RAG vector database
└── uploaded_docs/      # Original PDF/TXT/MD files
```

---

## ⚠️ Troubleshooting

### RAG Service Won't Start
```bash
# Check ChromaDB permissions
oc exec l1-integrated -- ls -la /pvc/chromadb/

# View RAG logs
oc logs l1-integrated | grep RAG
```

### AI Model Load Failure
```bash
# Check model file
oc exec l1-integrated -- ls -lh /models/mistral.gguf

# Check memory usage
oc exec l1-integrated -- free -h
```

### PVC Not Initialized
```bash
# Check init container logs
oc logs l1-integrated -c init-pvc

# Manually initialize
oc exec l1-integrated -- mkdir -p /pvc/{models,input_files,feature_history,chromadb,uploaded_docs}
```

---

## 🎯 Quick Reference

| Service | Port | Path | Purpose |
|---------|------|------|---------|
| Web App | 5000 | / | Main UI + API |
| RAG Service | 8001 | /rag/* | Knowledge Base |
| AI Inference | 8000 | /generate | LLM Streaming |

---

**Build Time**: ~10-15 minutes (with GGUF model)
**Image Size**: ~6-8 GB
**Memory Required**: 8GB+ (for Mistral-7B)
