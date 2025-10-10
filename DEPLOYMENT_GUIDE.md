# ML System Deployment Guide

## 🏗️ Architecture Overview

### PVC-Based Incremental Learning System
The ML analyzer uses a **shared Persistent Volume Claim (PVC)** that multiple pods can mount simultaneously:

```
┌─────────────────────────────────────────────┐
│     l1-ml-storage-pvc (20Gi)                │
│  ┌─────────────────────────────────────┐   │
│  │  /models/        - ML model files    │   │
│  │  /input_files/   - PCAP queue       │◄──┼── Your App writes here
│  │  /feature_history/ - Training data   │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
        ▲                           ▲
        │                           │
   ML Analyzer Pod            Your Application Pod
   (reads & processes)        (writes PCAP files)
```

### Automatic Triggering Workflow
1. **Your Application** copies `.pcap` file → `/pvc/input_files/`
2. **ML Analyzer** (watch mode) detects new file every 10 seconds
3. **Feature Extraction** from PCAP → saves to `/pvc/feature_history/`
4. **Incremental Learning** retrains models every 10 files
5. **Anomalies Detected** → stored in ClickHouse database
6. **Dashboard Updates** with real-time results

---

## 📋 Deployment Steps

### Step 1: Create Namespace
```bash
kubectl create namespace l1-app-ai
```

### Step 2: Deploy PVC and ML Analyzer
```bash
# Apply the PVC configuration (creates storage + deployment)
kubectl apply -f k8s-ml-pvc.yaml

# Verify PVC is bound
kubectl get pvc -n l1-app-ai
# Expected: l1-ml-storage-pvc   Bound   pvc-xxx   20Gi   RWO

# Check ML analyzer pod status
kubectl get pods -n l1-app-ai
# Expected: ml-analyzer-deployment-xxx   1/1   Running
```

### Step 3: Create ConfigMap with Python Scripts
```bash
# Create ConfigMap containing all ML analyzer scripts
kubectl create configmap ml-analyzer-scripts \
  --from-file=ml_anomaly_detection.py \
  --from-file=folder_anomaly_analyzer_clickhouse.py \
  --from-file=unified_l1_analyzer.py \
  --from-file=server/services/ue_analyzer.py \
  --from-file=server/services/ml_ue_analyzer.py \
  -n l1-app-ai

# Verify ConfigMap
kubectl describe configmap ml-analyzer-scripts -n l1-app-ai
```

### Step 4: Deploy Your Application (PVC Writer)
```bash
# Deploy your application that writes PCAP files
kubectl apply -f k8s-app-pvc-example.yaml

# Your app should mount the same PVC:
#   volumeMounts:
#   - name: shared-ml-storage
#     mountPath: /app/output
#     subPath: input_files  # Write to input_files directory
```

### Step 5: Verify Watch Mode is Running
```bash
# Check ML analyzer logs
kubectl logs -f deployment/ml-analyzer-deployment -n l1-app-ai

# Expected output:
# 🔍 WATCH MODE: Monitoring /pvc/input_files for new files...
#    Check interval: 10 seconds
```

---

## 🔄 How File Processing Works

### Automatic File Detection
The ML analyzer runs in **watch mode** with these parameters:
- **Check Interval**: 10 seconds (configurable via `--interval` flag)
- **Monitored Directory**: `/pvc/input_files`
- **Supported Files**: `.pcap`, `.cap`, `.pcapng`, `.txt`, `.log`

### When Your App Copies a File:
```bash
# Your application writes:
cp network-capture.pcap /shared-pvc/input_files/

# Within 10 seconds:
# 1. ML analyzer detects new file
# 2. Extracts 16D features
# 3. Runs ensemble ML analysis (Isolation Forest, DBSCAN, SVM, LOF)
# 4. Saves features to /pvc/feature_history/accumulated_features.npy
# 5. Increments counter
# 6. Stores anomalies in ClickHouse
```

### Incremental Learning Cycle:
- **Files 1-9**: Inference mode, features accumulate
- **File 10**: Triggers retraining on ALL accumulated features
  - Models retrain using complete dataset
  - Counter resets to 0
  - Accumulated features deleted
  - New models saved to PVC
- **Files 11-20**: Repeat with improved models

---

## 📊 Monitoring and Verification

### Check ML Processing Status
```bash
# View real-time logs
kubectl logs -f deployment/ml-analyzer-deployment -n l1-app-ai

# Check files processed
kubectl exec -it deployment/ml-analyzer-deployment -n l1-app-ai -- \
  ls -la /pvc/input_files/

# View ML metadata
kubectl exec -it deployment/ml-analyzer-deployment -n l1-app-ai -- \
  cat /pvc/models/metadata.json
```

### Expected Metadata After 10 Files:
```json
{
  "files_processed": 0,
  "last_retrain": "2025-10-10T12:34:56",
  "created_at": "2025-10-10T10:00:00",
  "model_versions": {
    "isolation_forest": "1.3.0",
    "one_class_svm": "1.3.0",
    "dbscan": "1.3.0"
  }
}
```

### Check Accumulated Features:
```bash
kubectl exec -it deployment/ml-analyzer-deployment -n l1-app-ai -- \
  ls -lh /pvc/feature_history/

# Before retraining (files 1-9):
# accumulated_features.npy (growing size)

# After retraining (file 10):
# (file deleted, ready for next cycle)
```

---

## 🚀 Example: Integrating Your Application

### Option 1: Deploy as Sidecar (Same Pod)
```yaml
spec:
  containers:
  - name: your-app
    image: your-app:latest
    volumeMounts:
    - name: shared-storage
      mountPath: /output
      subPath: input_files
  
  - name: ml-analyzer
    image: ml-analyzer:latest
    volumeMounts:
    - name: shared-storage
      mountPath: /pvc/input_files
      subPath: input_files
  
  volumes:
  - name: shared-storage
    persistentVolumeClaim:
      claimName: l1-ml-storage-pvc
```

### Option 2: Separate Pods (Shared PVC)
```yaml
# Your App Pod
volumeMounts:
- name: output-storage
  mountPath: /app/pcap-output
  subPath: input_files

volumes:
- name: output-storage
  persistentVolumeClaim:
    claimName: l1-ml-storage-pvc

# ML Analyzer Pod (already deployed)
# Automatically detects files in /pvc/input_files
```

---

## 🛠️ Configuration Options

### ML Analyzer Environment Variables:
```yaml
env:
- name: ML_MODELS_DIR
  value: "/pvc/models"
- name: INPUT_FILES_DIR
  value: "/pvc/input_files"
- name: FEATURE_HISTORY_DIR
  value: "/pvc/feature_history"
- name: RETRAIN_THRESHOLD
  value: "10"  # Retrain every N files
- name: WATCH_INTERVAL
  value: "10"  # Check for new files every 10 seconds
```

### Command Line Flags:
```bash
# Watch mode (default in k8s)
python3 folder_anomaly_analyzer_clickhouse.py --watch --input-dir /pvc/input_files

# Custom interval (check every 30 seconds)
python3 folder_anomaly_analyzer_clickhouse.py --watch --interval 30

# Single-run mode (process once and exit)
python3 folder_anomaly_analyzer_clickhouse.py /pvc/input_files

# Dummy mode (no database writes, console only)
python3 folder_anomaly_analyzer_clickhouse.py --watch --dummy
```

---

## ❓ FAQ

### Q: Why don't I need a temporary upload pod?
**A:** You only need temporary pods for manual testing. In production, your application writes directly to the shared PVC, and the ML analyzer automatically processes files.

### Q: Do multiple pods get created?
**A:** No. You have:
- 1 PVC (storage)
- 1 ML Analyzer pod (reader/processor)
- 1 Your Application pod (writer)

Both pods mount the SAME PVC at different paths.

### Q: What if my app writes files faster than ML can process?
**A:** The watch mode processes files sequentially. Files queue up in `/pvc/input_files` and are processed in order. Increase `--interval` if needed.

### Q: How do I stop the ML analyzer?
```bash
# Delete the deployment
kubectl delete deployment ml-analyzer-deployment -n l1-app-ai

# PVC and data remain intact
```

### Q: How do I restart with fresh models?
```bash
# Delete accumulated features and metadata
kubectl exec -it deployment/ml-analyzer-deployment -n l1-app-ai -- \
  rm -rf /pvc/models/* /pvc/feature_history/*

# Restart pod
kubectl rollout restart deployment ml-analyzer-deployment -n l1-app-ai
```

---

## 🎯 Summary

✅ **One PVC** shared between ML analyzer and your application  
✅ **Automatic triggering** via watch mode (10-second polling)  
✅ **Incremental learning** with 10-file retraining cycle  
✅ **No manual intervention** required after deployment  
✅ **Real-time anomaly detection** stored in ClickHouse  
✅ **Dashboard integration** for live monitoring  

Your application just needs to copy PCAP files to `/pvc/input_files/`, and the ML system handles the rest!
