#!/bin/bash

echo "Checking PVC Status"
echo "==================="
echo ""

PROJECT_NAME="l1-app-ai"

echo "1. PVC Status:"
oc get pvc -n $PROJECT_NAME

echo ""
echo "2. Detailed PVC Info:"
oc describe pvc tslam-model-storage-pvc -n $PROJECT_NAME 2>&1 || echo "PVC not found"

echo ""
echo "3. Storage Classes:"
oc get storageclass

echo ""
echo "4. Current pod status:"
oc get pod model-uploader -n $PROJECT_NAME 2>&1 || echo "Pod not found"

echo ""
echo "5. Pod events:"
oc describe pod model-uploader -n $PROJECT_NAME 2>&1 | grep -A 10 "Events:" || echo "No pod events"
