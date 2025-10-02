#!/bin/bash

echo "Building TSLAM Container in OpenShift"
echo "======================================"
echo ""

MODEL_SOURCE="/home/cloud-user/pjoe/model"
PROJECT_NAME="l1-app-ai"

# Check if model source exists
if [ ! -d "$MODEL_SOURCE" ]; then
    echo "ERROR: Model source directory $MODEL_SOURCE does not exist!"
    exit 1
fi

echo "Step 1: Creating build context..."
rm -rf build-context
mkdir -p build-context/model
cp -r $MODEL_SOURCE/* build-context/model/
cp Dockerfile.tslam build-context/Dockerfile
cp tslam-container-server.py build-context/

echo "Step 2: Checking model files..."
MODEL_FILE_COUNT=$(find build-context/model -type f | wc -l)
echo "   Model files to include: $MODEL_FILE_COUNT"
ls -lh build-context/model/ | head -10

echo ""
echo "Step 3: Creating BuildConfig and ImageStream..."
oc apply -f tslam-buildconfig.yaml

echo ""
echo "Step 4: Starting build in OpenShift..."
echo "   (This will upload your model files and build the container in the cluster)"
echo ""

cd build-context
oc start-build tslam-with-model --from-dir=. --follow -n $PROJECT_NAME

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed!"
    exit 1
fi

cd ..

echo ""
echo "✅ Image built successfully in OpenShift!"
echo ""
echo "Image available as: tslam-with-model:latest in ImageStream"
echo ""
echo "Next step: Deploy with ./deploy-pod.sh"
