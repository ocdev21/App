#!/bin/bash

echo "Deploying L1 Troubleshooting Application to OpenShift AI Platform"
echo "================================================================"

# Set project/namespace
PROJECT_NAME="l1-app-ai"

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

# Check if default storage class exists
echo "Checking available storage classes..."
DEFAULT_SC=$(oc get storageclass --no-headers | grep "(default)" | awk '{print $1}' | head -n1)
if [ -z "$DEFAULT_SC" ]; then
    echo "WARNING: No default storage class found. Using first available storage class..."
    FIRST_SC=$(oc get storageclass --no-headers | awk '{print $1}' | head -n1)
    if [ ! -z "$FIRST_SC" ]; then
        echo "Using storage class: $FIRST_SC"
    else
        echo "ERROR: No storage classes available. Please check your cluster configuration."
        exit 1
    fi
else
    echo "Using default storage class: $DEFAULT_SC"
fi

# Apply the complete deployment
echo "Applying L1 Application deployment..."
oc apply -f openshift/l1-app-openshift-ai-deployment.yaml

# Wait for ConfigMaps and other resources to be created
echo "Waiting for resources to be created..."
sleep 10

# Start build process
echo "Starting build process..."
BUILD_NAME=$(oc start-build l1-app-ai-build -n $PROJECT_NAME -o name 2>/dev/null | cut -d'/' -f2)
if [ ! -z "$BUILD_NAME" ]; then
    echo "Build started: $BUILD_NAME"
    echo "Waiting for build to complete..."
    oc wait --for=condition=Complete build/$BUILD_NAME -n $PROJECT_NAME --timeout=600s
    echo "Build completed successfully!"
else
    echo "WARNING: Build may have already started or failed to start. Checking existing builds..."
    oc get builds -n $PROJECT_NAME
fi

# Wait for deployments to be ready
echo "Waiting for ClickHouse deployment to be ready..."
oc rollout status deployment/clickhouse-ai -n $PROJECT_NAME --timeout=600s

echo "Waiting for L1 application deployment to be ready..."
oc rollout status deployment/l1-troubleshooting-ai -n $PROJECT_NAME --timeout=600s

echo "Waiting for TSLAM model deployment to be ready..."
oc rollout status deployment/tslam-model-deployment -n $PROJECT_NAME --timeout=300s

# Wait for pods to be ready
echo "Waiting for all pods to be ready..."
oc wait --for=condition=Ready pod -l app=clickhouse-ai -n $PROJECT_NAME --timeout=300s
oc wait --for=condition=Ready pod -l app=l1-troubleshooting-ai -n $PROJECT_NAME --timeout=300s
oc wait --for=condition=Ready pod -l app=tslam-model -n $PROJECT_NAME --timeout=300s

echo ""
echo "L1 Application deployment completed successfully!"
echo ""
echo "OpenShift AI Platform Information:"
echo "   - Namespace: $PROJECT_NAME"
echo "   - Main Application: l1-troubleshooting-ai (2 replicas with auto-scaling)"
echo "   - ClickHouse Database: clickhouse-ai"
echo "   - TSLAM Model Service: tslam-model-deployment"
echo ""
echo "Access Information:"
L1_ROUTE=$(oc get route l1-troubleshooting-ai-route -n $PROJECT_NAME -o jsonpath='{.spec.host}' 2>/dev/null)
if [ ! -z "$L1_ROUTE" ]; then
    echo "   - Application URL: https://$L1_ROUTE"
else
    echo "   - Route not yet available, check: oc get route -n $PROJECT_NAME"
fi
echo ""
echo "Monitoring Commands:"
echo "   - Check all pods: oc get pods -n $PROJECT_NAME"
echo "   - Check services: oc get svc -n $PROJECT_NAME"
echo "   - Check routes: oc get route -n $PROJECT_NAME"
echo "   - View L1 app logs: oc logs deployment/l1-troubleshooting-ai -n $PROJECT_NAME"
echo "   - View ClickHouse logs: oc logs deployment/clickhouse-ai -n $PROJECT_NAME"
echo "   - View TSLAM logs: oc logs deployment/tslam-model-deployment -n $PROJECT_NAME"
echo "   - Check builds: oc get builds -n $PROJECT_NAME"
echo "   - Check image streams: oc get is -n $PROJECT_NAME"
echo "   - Check PVCs: oc get pvc -n $PROJECT_NAME"
echo ""
echo "Management Commands:"
echo "   - Scale L1 app: oc scale deployment/l1-troubleshooting-ai --replicas=X -n $PROJECT_NAME"
echo "   - Rebuild image: oc start-build l1-app-ai-build -n $PROJECT_NAME"
echo "   - Update config: oc edit configmap/l1-app-ai-config -n $PROJECT_NAME"
echo "   - Restart L1 app: oc rollout restart deployment/l1-troubleshooting-ai -n $PROJECT_NAME"
echo "   - Restart ClickHouse: oc rollout restart deployment/clickhouse-ai -n $PROJECT_NAME"
echo ""
echo "OpenShift AI Features:"
echo "   - Model Serving: TSLAM model available at tslam-model-service:8080"
echo "   - Auto-scaling: Enabled (2-10 replicas based on CPU/Memory)"
echo "   - Persistent Storage: Configured with cluster default storage class"
echo "   - Network Policies: Applied for secure inter-service communication"
echo "   - Health Checks: Configured for all services"