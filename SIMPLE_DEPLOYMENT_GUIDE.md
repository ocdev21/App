# Simple ML Setup for Existing l1-integrated Pod

## 🎯 Your Setup (Single Pod)

```
┌─────────────────────────────────────────┐
│  l1-integrated Pod                      │
│  ┌──────────────────────────────────┐   │
│  │  Web App + AI + ML Code          │   │
│  │  (all in one container)          │   │
│  └──────────────────────────────────┘   │
│              ▼                           │
│  ┌──────────────────────────────────┐   │
│  │  /pvc (PVC Mount)                │   │
│  │  ├── models/        (.pkl files) │   │
│  │  ├── input_files/   (PCAP files) │   │
│  │  └── feature_history/ (training) │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## 📋 Deployment Steps

### Step 1: Create the PVC
```bash
# Create PVC for ML data storage
kubectl apply -f openshift/l1-ml-pvc-simple.yaml

# Verify
kubectl get pvc -n l1-app-ai
# Expected: l1-ml-data-pvc   Bound   20Gi
```

### Step 2: Update Your Existing Pod
```bash
# Delete old pod (data is separate, so safe)
kubectl delete pod l1-integrated -n l1-app-ai

# Apply updated pod with PVC mount
kubectl apply -f openshift/tslam-pod-with-pvc.yaml

# Verify pod is running
kubectl get pod l1-integrated -n l1-app-ai
```

### Step 3: Verify PVC Mount
```bash
# Check if /pvc is mounted
kubectl exec -it l1-integrated -n l1-app-ai -- ls -la /pvc

# Expected output:
# drwxr-xr-x  5 root root 4096 Oct 10 12:00 .
# drwxr-xr-x 20 root root 4096 Oct 10 12:00 ..
# drwxr-xr-x  2 root root 4096 Oct 10 12:00 models
# drwxr-xr-x  2 root root 4096 Oct 10 12:00 input_files
# drwxr-xr-x  2 root root 4096 Oct 10 12:00 feature_history
```

## 📂 Manual File Copying

### From Your Local Machine
```bash
# Copy PCAP file to the pod
kubectl cp your-network-file.pcap \
  l1-app-ai/l1-integrated:/pvc/input_files/

# Copy multiple files
kubectl cp ./pcap-folder/ \
  l1-app-ai/l1-integrated:/pvc/input_files/

# Verify files are there
kubectl exec -it l1-integrated -n l1-app-ai -- \
  ls -lh /pvc/input_files/
```

### From Within the Pod
```bash
# Access the pod
kubectl exec -it l1-integrated -n l1-app-ai -- bash

# Copy files from any location
cp /tmp/capture.pcap /pvc/input_files/
cp /app/data/*.pcap /pvc/input_files/
```

## 🚀 Running ML Analysis

### Option 1: Manual Single Run
```bash
# Access the pod
kubectl exec -it l1-integrated -n l1-app-ai -- bash

# Run ML analysis on files in PVC
cd /app
python3 folder_anomaly_analyzer_clickhouse.py /pvc/input_files

# Output:
# - Processes all PCAP/text files
# - Extracts features
# - Runs ML ensemble analysis
# - Saves models to /pvc/models/*.pkl
# - Accumulates features in /pvc/feature_history/
# - Retrains every 10 files
# - Stores anomalies in ClickHouse
```

### Option 2: Watch Mode (Continuous)
```bash
# Access the pod
kubectl exec -it l1-integrated -n l1-app-ai -- bash

# Start watch mode (monitors for new files)
python3 folder_anomaly_analyzer_clickhouse.py --watch --input-dir /pvc/input_files

# Now just copy files and they auto-process:
# In another terminal:
kubectl cp newfile.pcap l1-app-ai/l1-integrated:/pvc/input_files/
```

### Option 3: From Your Application Code
```python
# Inside your l1-integrated app code:
import subprocess

def analyze_pcap(pcap_file_path):
    # Copy file to ML input directory
    shutil.copy(pcap_file_path, '/pvc/input_files/')
    
    # Trigger ML analysis
    subprocess.run([
        'python3', 
        'folder_anomaly_analyzer_clickhouse.py',
        '/pvc/input_files'
    ])
```

## 📊 Incremental Learning Flow

### Automatic Model Improvement
```
File 1  → Extract features → Save to /pvc/feature_history/
File 2  → Extract features → Append to accumulated_features.npy
File 3  → Extract features → Append...
...
File 9  → Extract features → Append (counter = 9)
File 10 → RETRAIN TRIGGER!
          ├─ Load all accumulated features
          ├─ Retrain models on complete dataset
          ├─ Save updated models to /pvc/models/
          ├─ Reset counter to 0
          └─ Delete accumulated features
File 11 → Start new cycle with improved models...
```

### Check ML Status
```bash
# View metadata
kubectl exec -it l1-integrated -n l1-app-ai -- \
  cat /pvc/models/metadata.json

# Expected output:
{
  "files_processed": 3,
  "last_retrain": "2025-10-10T12:34:56",
  "created_at": "2025-10-10T10:00:00",
  "model_versions": {...}
}

# List model files
kubectl exec -it l1-integrated -n l1-app-ai -- \
  ls -lh /pvc/models/

# Expected:
# isolation_forest_model.pkl
# one_class_svm_model.pkl
# dbscan_model.pkl
# scaler_model.pkl
# metadata.json
```

## 🔧 Troubleshooting

### Issue: PVC not mounted
```bash
# Check PVC status
kubectl get pvc l1-ml-data-pvc -n l1-app-ai

# If "Pending", check events
kubectl describe pvc l1-ml-data-pvc -n l1-app-ai
```

### Issue: Permission denied
```bash
# Fix permissions inside pod
kubectl exec -it l1-integrated -n l1-app-ai -- \
  chmod -R 777 /pvc
```

### Issue: Files not processing
```bash
# Check if files exist
kubectl exec -it l1-integrated -n l1-app-ai -- \
  ls -la /pvc/input_files/

# Check ML analyzer logs
kubectl logs l1-integrated -n l1-app-ai | grep -i "ml\|anomaly"
```

## 📁 PVC Directory Structure

After deployment, your PVC will have:
```
/pvc/
├── models/                          # ML model persistence
│   ├── isolation_forest_model.pkl
│   ├── one_class_svm_model.pkl
│   ├── dbscan_model.pkl
│   ├── scaler_model.pkl
│   └── metadata.json
│
├── input_files/                     # Where you copy PCAP files
│   ├── capture1.pcap
│   ├── capture2.pcap
│   └── ue_events.txt
│
└── feature_history/                 # Incremental learning data
    └── accumulated_features.npy     # (deleted after retraining)
```

## 🎯 Quick Reference

### Copy file to pod:
```bash
kubectl cp file.pcap l1-app-ai/l1-integrated:/pvc/input_files/
```

### Run ML analysis:
```bash
kubectl exec -it l1-integrated -n l1-app-ai -- \
  python3 folder_anomaly_analyzer_clickhouse.py /pvc/input_files
```

### Check models:
```bash
kubectl exec -it l1-integrated -n l1-app-ai -- \
  ls -lh /pvc/models/
```

### View metadata:
```bash
kubectl exec -it l1-integrated -n l1-app-ai -- \
  cat /pvc/models/metadata.json
```

---

## ✅ Summary

1. **One Pod**: Everything runs in `l1-integrated`
2. **One PVC**: `l1-ml-data-pvc` (20GB) stores models + inputs
3. **Manual Copy**: Use `kubectl cp` to upload files
4. **Auto Learning**: Models improve every 10 files
5. **Simple Trigger**: Run Python script manually or via app code

No complexity, no watch modes required (unless you want them), just simple file copy → run analysis!
