# L1 Integrated Container - OpenShift Deployment

## 🚀 Quick Start

### For Embedded Model Deployment (Recommended)
**Use this if you're experiencing PVC/storage provisioning issues**

**One-Command Build:**
```bash
cd openshift
chmod +x build-embedded.sh
./build-embedded.sh
```

📖 Full Guide: **[BUILD_INSTRUCTIONS_EMBEDDED.md](BUILD_INSTRUCTIONS_EMBEDDED.md)**  
📖 Quick Reference: **[QUICKSTART.md](QUICKSTART.md)**

**Advantages:**
- ✅ No PVC required - works on any cluster
- ✅ No storage class dependencies
- ✅ Automated build process - no manual steps
- ✅ Instant deployment
- ✅ Model embedded in Docker image (~10GB)

---

### For PVC-Based Deployment (Legacy)
**Only use if your cluster has working persistent storage**

📖 See: **[BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)**

**Requirements:**
- ⚠️ Working storage class (gp3-csi, standard-csi, etc.)
- ⚠️ PVC must successfully bind
- ⚠️ Manual model copy via `oc cp`

---

## 📁 Files

- **`Dockerfile.tslam`** - Dockerfile for building integrated container
- **`l1-pod-embedded.yaml`** - Pod YAML for embedded model (no PVC)
- **`tslam-pod-with-pvc.yaml`** - Pod YAML for PVC-based deployment
- **`start-services.sh`** - Startup script for all services
- **`gguf-inference-server.py`** - AI inference server
- **`rag_server.py`** - RAG service server

---

## ⚠️ Known Issues

### Storage Provisioning Errors
If you see errors like:
```
FailedAttachVolume: AttachVolume.Attach failed
Volume attachments can not be created (HTTP 400)
```

**Solution:** Use the embedded model approach instead (see BUILD_INSTRUCTIONS_EMBEDDED.md)

---

## 📊 Architecture

### Embedded Model (Recommended)
```
Container Image (~10GB)
├── /app/models/mistral.gguf (embedded, 4.1GB)
├── /app/ml_data/ (ephemeral)
├── /app/chromadb/ (ephemeral)
└── /app/uploaded_docs/ (ephemeral)
```

### PVC-Based (Legacy)
```
Container Image (~6GB)
├── /models/ (PVC mount)
├── /app/ml_data/ (ephemeral)
├── /app/chromadb/ (ephemeral)
└── /app/uploaded_docs/ (ephemeral)
```

---

**For deployment instructions, see the appropriate BUILD_INSTRUCTIONS file above.**
