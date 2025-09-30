#!/bin/bash

echo "Deploying TSLAM Pod"
echo "==================="
echo ""

PROJECT_NAME="l1-app-ai"

echo "Step 1: Cleaning up old resources..."
oc delete deployment tslam-container -n $PROJECT_NAME --ignore-not-found=true
oc delete pod tslam-container -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-container-service -n $PROJECT_NAME --ignore-not-found=true

sleep 5

echo ""
echo "Step 2: Deploying TSLAM pod..."
oc apply -f tslam-pod.yaml

echo ""
echo "Step 3: Waiting for pod to be ready..."
oc wait --for=condition=Ready pod/tslam-container -n $PROJECT_NAME --timeout=600s

if [ $? -ne 0 ]; then
    echo ""
    echo "Pod not ready yet. Checking status..."
    oc get pod tslam-container -n $PROJECT_NAME
    echo ""
    echo "Pod logs:"
    oc logs tslam-container -n $PROJECT_NAME 2>&1 | tail -50
    echo ""
    echo "Pod events:"
    oc describe pod tslam-container -n $PROJECT_NAME | tail -20
    exit 1
fi

echo ""
echo "Step 4: Checking pod status..."
oc get pod tslam-container -n $PROJECT_NAME
oc get service tslam-container-service -n $PROJECT_NAME

echo ""
echo "✅ TSLAM Pod deployment complete!"
echo ""
echo "To test:"
echo "  oc exec -it tslam-container -n $PROJECT_NAME -- curl http://localhost:8000/health"
echo ""
echo "To check logs:"
echo "  oc logs -f tslam-container -n $PROJECT_NAME"
echo ""
echo "Service endpoint: tslam-container-service:8000"
