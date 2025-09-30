#!/bin/bash

echo "TSLAM Model Upload Script (Using rsync)"
echo "========================================"
echo ""

PROJECT_NAME="l1-app-ai"
MODEL_SOURCE="/home/cloud-user/pjoe/model"

# Check if source directory exists
if [ ! -d "$MODEL_SOURCE" ]; then
    echo "ERROR: Source directory $MODEL_SOURCE does not exist!"
    echo "Please verify the path to your TSLAM model files."
    exit 1
fi

# Clean up old resources
echo "Step 1: Cleaning up old resources..."
oc delete pod model-uploader -n $PROJECT_NAME --ignore-not-found=true
oc delete job model-uploader-job -n $PROJECT_NAME --ignore-not-found=true
sleep 5

echo "Step 2: Creating uploader job..."
oc apply -f model-uploader-job.yaml

echo "Step 3: Waiting for job pod to be ready..."
sleep 10

# Get the pod name from the job
POD_NAME=$(oc get pods -n $PROJECT_NAME -l app=model-uploader --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "Waiting for pod to start..."
    sleep 20
    POD_NAME=$(oc get pods -n $PROJECT_NAME -l app=model-uploader -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [ -z "$POD_NAME" ]; then
    echo "ERROR: Pod not found or not running"
    echo "Job status:"
    oc get job model-uploader-job -n $PROJECT_NAME
    echo ""
    echo "Pod status:"
    oc get pods -n $PROJECT_NAME -l app=model-uploader
    echo ""
    echo "Checking events:"
    oc describe job model-uploader-job -n $PROJECT_NAME | tail -20
    exit 1
fi

echo "Pod name: $POD_NAME"

echo "Step 4: Waiting for pod to be fully ready..."
oc wait --for=condition=Ready pod/$POD_NAME -n $PROJECT_NAME --timeout=180s

if [ $? -ne 0 ]; then
    echo "ERROR: Pod failed to become ready"
    echo "Checking pod status..."
    oc get pod $POD_NAME -n $PROJECT_NAME
    oc describe pod $POD_NAME -n $PROJECT_NAME | tail -30
    exit 1
fi

echo "Step 5: Copying TSLAM model files using rsync..."
echo "   Source: $MODEL_SOURCE"
echo "   Destination: $POD_NAME:/models/tslam-4b/"
echo "   (This may take several minutes)"
echo ""

# Use rsync which is more reliable for large transfers
oc rsync $MODEL_SOURCE/ $PROJECT_NAME/$POD_NAME:/models/tslam-4b/ --no-perms=true

if [ $? -ne 0 ]; then
    echo ""
    echo "WARNING: rsync failed, trying with oc cp..."
    oc cp $MODEL_SOURCE/ $PROJECT_NAME/$POD_NAME:/models/tslam-4b/
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to copy model files"
        exit 1
    fi
fi

echo ""
echo "Step 6: Verifying uploaded files..."
oc exec $POD_NAME -n $PROJECT_NAME -- ls -lh /models/tslam-4b/ | head -20

echo ""
echo "File count:"
oc exec $POD_NAME -n $PROJECT_NAME -- find /models/tslam-4b -type f | wc -l

echo ""
echo "Total size:"
oc exec $POD_NAME -n $PROJECT_NAME -- du -sh /models/tslam-4b/

echo ""
echo "✅ Model upload complete!"
echo ""
echo "Next steps:"
echo "  1. Deploy TSLAM service: ./deploy-real-model.sh"
echo "  2. Clean up uploader job: oc delete job model-uploader-job -n $PROJECT_NAME"
