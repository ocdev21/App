#!/bin/bash

echo "Deploying TSLAM Container with Embedded Model"
echo "=============================================="
echo ""

PROJECT_NAME="l1-app-ai"

echo "Step 1: Cleaning up old deployments..."
oc delete deployment tslam-hostpath-model -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-real-model -n $PROJECT_NAME --ignore-not-found=true
oc delete deployment tslam-simple -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-hostpath-service -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-real-model-service -n $PROJECT_NAME --ignore-not-found=true
oc delete service tslam-simple-service -n $PROJECT_NAME --ignore-not-found=true
oc delete job model-uploader-job -n $PROJECT_NAME --ignore-not-found=true
oc delete pod model-uploader -n $PROJECT_NAME --ignore-not-found=true

echo ""
echo "Step 2: Deploying TSLAM container..."
oc apply -f tslam-container-deployment.yaml

echo ""
echo "Step 3: Waiting for deployment to be ready..."
oc rollout status deployment/tslam-container -n $PROJECT_NAME --timeout=600s

echo ""
echo "Step 4: Checking deployment status..."
oc get pods -l app=tslam-container -n $PROJECT_NAME
oc get service tslam-container-service -n $PROJECT_NAME

echo ""
echo "✅ TSLAM Container deployment complete!"
echo ""
echo "To test:"
echo "  Health: oc exec -it deployment/tslam-container -n $PROJECT_NAME -- curl http://tslam-container-service:8000/health"
echo ""
echo "To check logs:"
echo "  oc logs -f deployment/tslam-container -n $PROJECT_NAME"
echo ""
echo "Service endpoint: tslam-container-service:8000"
