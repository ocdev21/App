# L1 Integrated Container - Build & Deploy Instructions (Embedded Model)

## 📦 What's Included

The container includes **3 integrated services** with **embedded AI model**:

1. **L1 Web Application** (Port 5000)
   - React frontend + Express backend
   - Anomaly detection dashboard
   - Knowledge Base UI

2. **RAG Service** (Port 8001)
   - ChromaDB vector database (ephemeral storage)
   - Sentence transformers embeddings
   - Flask API for semantic search

3. **AI Inference Server** (Port 8000)
   - **Mistral-7B GGUF model (embedded in image)**
   - CTransformers runtime
   - Streaming AI recommendations

---

## 🏗️ Build With Embedded Model (Automated)

### Prerequisites
- **Mistral GGUF model** at: `/home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf`
  - ✅ **Model will be automatically embedded in the Docker image**
  - ✅ No PVC needed - works immediately on any cluster
  - ⚠️ Image size: ~10GB (model included)
- Podman or Docker installed
- Private registry access: `10.0.1.224:5000`

### Option 1: Automated Build (Recommended)

**One command to build everything:**

```bash
cd openshift
chmod +x build-embedded.sh
./build-embedded.sh
```

**What the script does:**
1. ✅ Automatically copies model from `/home/cloud-user/pjoe/model/mistral7b/` to build context
2. ✅ Builds Docker image with embedded model (~10GB)
3. ✅ Pushes to registry `10.0.1.224:5000/l1-integrated:latest`
4. ✅ Cleans up temporary files automatically
5. ✅ Shows progress and status messages

**Expected output:**
```
========================================
  L1 Integrated - Automated Build
  (Embedded Model Architecture)
========================================

[INFO] Step 1/5: Verifying model file...
[SUCCESS] Model found: 4.1G at /home/cloud-user/pjoe/model/mistral7b/...

[INFO] Step 2/5: Copying model to build context...
[SUCCESS] Model copied to build context

[INFO] Step 3/5: Building Docker image (this may take 5-10 minutes)...
[SUCCESS] Docker image built successfully

[INFO] Step 4/5: Pushing image to registry...
[SUCCESS] Image pushed to 10.0.1.224:5000/l1-integrated:latest

[INFO] Step 5/5: Cleaning up temporary files...
[SUCCESS] Build context cleaned

========================================
  Build Complete!
========================================
```

### Option 2: Manual Build (Alternative)

If you prefer manual control:

```bash
cd openshift

# Copy model to build context
cp /home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf \
   ./mistral-7b-instruct-v0.2.Q4_K_M.gguf

# Verify model is present
ls -lh mistral-7b-instruct-v0.2.Q4_K_M.gguf

# Build with model embedded
podman build --no-cache \
  -t 10.0.1.224:5000/l1-integrated:latest \
  -f Dockerfile.tslam .

# Push to registry
podman push 10.0.1.224:5000/l1-integrated:latest

# Clean up
rm mistral-7b-instruct-v0.2.Q4_K_M.gguf
```

### Verify Image

```bash
# Check image size (expect ~10GB with embedded model)
podman images | grep l1-integrated

# Verify model is embedded
podman run --rm 10.0.1.224:5000/l1-integrated:latest ls -lh /app/models/
# Should show: mistral.gguf ~4.1G
```

---

## 🚀 Deploy to OpenShift (No PVC Required!)

### Step 1: Clean Up Old Resources

```bash
# Login to OpenShift
oc login <cluster-url>
oc project l1-app-ai

# Force delete old pod (if exists)
oc delete pod l1-integrated -n l1-app-ai --force --grace-period=0 --ignore-not-found=true

# Delete old PVCs if switching from PVC-based deployment
oc delete pvc l1-app-ai-model-pvc l1-model-storage -n l1-app-ai --force --grace-period=0 --ignore-not-found=true

# Wait for cleanup
sleep 5
```

### Step 2: Deploy Pod (Model Already Embedded!)

```bash
# Deploy the integrated pod - NO PVC needed!
oc apply -f openshift/l1-pod-embedded.yaml

# Monitor startup
oc logs -f l1-integrated -n l1-app-ai
```

**Expected startup output:**
```
========================================
Starting L1 Integrated Services
========================================

[1/3] Starting RAG Service (port 8001)...
  RAG Service initialized successfully

Checking for GGUF model...
  Model found: 4.1G at /app/models/mistral.gguf

[2/3] Starting AI Inference Server (port 8000)...
  AI Server initialized successfully

[3/3] Starting L1 Web Application (port 5000)...

========================================
Services Running:
  - L1 Web App:     http://0.0.0.0:5000
  - RAG Service:    http://0.0.0.0:8001
  - AI Inference:   http://0.0.0.0:8000
========================================
```

### Step 3: Verify Services

```bash
# Check pod status
oc get pods -n l1-app-ai

# Verify model is accessible
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/models/mistral.gguf

# Test AI service
oc exec l1-integrated -n l1-app-ai -- curl -s http://localhost:8000/health
```

### Step 4: Access Application

```bash
# Get the public URL
oc get route l1-integrated-route -n l1-app-ai -o jsonpath='{.spec.host}'

# Open in browser
echo "https://$(oc get route l1-integrated-route -n l1-app-ai -o jsonpath='{.spec.host}')"
```

---

## 📂 Copy PCAP Files for ML Analysis

The ML analyzer processes PCAP files from `/app/ml_data/input_files/`. Here's how to upload files:

### Method 1: Copy Single PCAP File

```bash
# Copy one file to the pod
oc cp /path/to/your/sample.pcap \
  l1-app-ai/l1-integrated:/app/ml_data/input_files/sample.pcap

# Verify file was copied
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/ml_data/input_files/
```

### Method 2: Copy Multiple PCAP Files

```bash
# Create a temporary directory with your PCAP files
mkdir -p /tmp/pcap_upload
cp /path/to/pcaps/*.pcap /tmp/pcap_upload/

# Copy entire directory to pod
oc cp /tmp/pcap_upload/. \
  l1-app-ai/l1-integrated:/app/ml_data/input_files/

# Verify all files copied
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/ml_data/input_files/
```

### Method 3: Copy from Specific Directory

```bash
# If you have PCAPs at a specific location
LOCAL_PCAP_DIR="/home/cloud-user/pcap_files"

# Copy all PCAP files
for file in $LOCAL_PCAP_DIR/*.pcap; do
  filename=$(basename "$file")
  oc cp "$file" l1-app-ai/l1-integrated:/app/ml_data/input_files/"$filename"
  echo "Copied: $filename"
done
```

### Trigger ML Analysis

Once files are copied, the ML analyzer will automatically process them:

```bash
# Check ML processing logs
oc logs l1-integrated -n l1-app-ai | grep -i "processing\|anomaly\|detection"

# Or monitor in real-time
oc logs -f l1-integrated -n l1-app-ai | grep --line-buffered -i "processing\|anomaly"
```

### View Analysis Results

```bash
# Check for generated ML models
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/ml_data/models/

# Check processed files count
oc exec l1-integrated -n l1-app-ai -- find /app/ml_data/input_files -name "*.pcap" | wc -l
```

---

## ✅ Advantages of Embedded Model Approach

### Benefits:
- ✅ **No storage provisioning issues** - bypasses PVC/Cinder problems entirely
- ✅ **Works on any cluster** - no dependency on storage classes
- ✅ **Instant deployment** - model loads immediately on pod start
- ✅ **Portable** - same image works everywhere
- ✅ **Simple deployment** - single YAML file, no PVC setup
- ✅ **Automated build** - one command builds everything

### Trade-offs:
- ⚠️ **Larger image size**: ~10GB (vs 6GB without model)
- ⚠️ **Longer build time**: +2-3 minutes to embed model
- ⚠️ **Ephemeral PCAP/RAG data**: Input files and ChromaDB reset on pod restart
  - Solution: Re-copy PCAP files after pod restart (quick operation)
  - Anomaly cases stored in PostgreSQL/ClickHouse persist

### Storage Architecture:
- **Model**: `/app/models/mistral.gguf` (embedded in image, 4.1GB)
- **ML Input Files**: `/app/ml_data/input_files/*.pcap` (ephemeral, copy on demand)
- **ML Models**: `/app/ml_data/models/*.pkl` (ephemeral, retrains from DB data)
- **ChromaDB**: `/app/chromadb` (ephemeral, rebuilds from DB on restart)
- **Uploaded Docs**: `/app/uploaded_docs` (ephemeral, re-upload after restart)
- **Database**: PostgreSQL/ClickHouse (persistent, external)

---

## 🔧 Troubleshooting

### Build Script Fails - Model Not Found
```bash
# Verify model path
ls -lh /home/cloud-user/pjoe/model/mistral7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf

# If path is different, edit build-embedded.sh:
nano openshift/build-embedded.sh
# Update MODEL_SOURCE variable
```

### Image Build Fails
```bash
# Ensure model is in openshift directory
ls -lh openshift/mistral-7b-instruct-v0.2.Q4_K_M.gguf

# Clean build cache
podman system prune -a

# Try manual build with verbose output
cd openshift
podman build --no-cache -f Dockerfile.tslam . 2>&1 | tee build.log
```

### Pod Fails to Start
```bash
# Check logs
oc logs l1-integrated -n l1-app-ai

# Verify image was pulled
oc describe pod l1-integrated -n l1-app-ai | grep -A5 Events

# Check pod events
oc get events -n l1-app-ai --sort-by='.lastTimestamp' | grep l1-integrated
```

### Model Not Found Error in Pod
```bash
# Verify model in image
oc exec l1-integrated -n l1-app-ai -- ls -la /app/models/

# If missing, rebuild image ensuring model is in build context
cd openshift
./build-embedded.sh
```

### PCAP Files Not Processing
```bash
# Check if files are in the correct directory
oc exec l1-integrated -n l1-app-ai -- ls -lh /app/ml_data/input_files/

# Check ML analyzer logs
oc logs l1-integrated -n l1-app-ai | grep -i "ml_analyzer\|folder_ml"

# Verify file permissions
oc exec l1-integrated -n l1-app-ai -- ls -la /app/ml_data/input_files/*.pcap
```

---

## 📊 Comparison: Embedded vs PVC Approach

| Aspect | Embedded Model | PVC-Based Model |
|--------|---------------|-----------------|
| Image Size | ~10GB | ~6GB |
| Build Process | ✅ Automated script | ⚠️ Manual steps |
| Deployment Speed | ⚡ Instant | ⏳ Copy model first |
| Storage Dependency | ✅ None | ⚠️ Requires PVC |
| Cluster Compatibility | ✅ Any cluster | ⚠️ Needs working storage |
| Model Updates | Rebuild image | Copy new model |
| PCAP Persistence | ❌ Copy on demand | ✅ Persistent |
| RAG Data Persistence | ❌ Ephemeral | ✅ Persistent |
| Best For | **Production (HA clusters)** | Development/Testing |

**Recommendation**: Use **embedded model** approach for production deployments to avoid storage infrastructure issues.

---

## 📚 Additional Resources

- **Quick Start**: See `QUICKSTART.md` for condensed commands
- **Dockerfile**: See `Dockerfile.tslam` for build details
- **Pod Spec**: See `l1-pod-embedded.yaml` for deployment config
- **Startup Script**: See `start-services.sh` for service initialization
