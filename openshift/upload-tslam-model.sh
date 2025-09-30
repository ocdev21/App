#!/bin/bash

echo "TSLAM Model Upload Script"
echo "========================="
echo ""

PROJECT_NAME="l1-app-ai"
MODEL_SOURCE="/home/cloud-user/pjoe/model"

# Check if source directory exists
if [ ! -d "$MODEL_SOURCE" ]; then
    echo "ERROR: Source directory $MODEL_SOURCE does not exist!"
    echo "Please verify the path to your TSLAM model files."
    exit 1
fi

echo "Step 1: Creating uploader pod..."
oc apply -f model-uploader-pod.yaml

echo "Step 2: Waiting for pod to be ready..."
oc wait --for=condition=Ready pod/model-uploader -n $PROJECT_NAME --timeout=120s

if [ $? -ne 0 ]; then
    echo "ERROR: Pod failed to become ready"
    echo "Checking pod status..."
    oc get pod model-uploader -n $PROJECT_NAME
    oc describe pod model-uploader -n $PROJECT_NAME | tail -20
    exit 1
fi

echo "Step 3: Copying TSLAM model files from local machine to cluster..."
echo "   Source: $MODEL_SOURCE"
echo "   Destination: model-uploader pod -> /models/tslam-4b/"
echo "   (This may take several minutes depending on model size)"
echo ""

oc cp $MODEL_SOURCE/ $PROJECT_NAME/model-uploader:/models/tslam-4b/

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to copy model files"
    exit 1
fi

echo ""
echo "Step 4: Verifying uploaded files..."
oc exec model-uploader -n $PROJECT_NAME -- ls -lh /models/tslam-4b/ | head -20

echo ""
echo "File count:"
oc exec model-uploader -n $PROJECT_NAME -- find /models/tslam-4b -type f | wc -l

echo ""
echo "Total size:"
oc exec model-uploader -n $PROJECT_NAME -- du -sh /models/tslam-4b/

echo ""
echo "✅ Model upload complete!"
echo ""
echo "Next steps:"
echo "  1. Deploy TSLAM service: ./deploy-real-model.sh"
echo "  2. Clean up uploader pod: oc delete pod model-uploader -n $PROJECT_NAME"
