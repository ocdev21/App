
#!/bin/bash

echo "Deploying L1 Troubleshooting Application to OpenShift AI (Debug Mode)"
echo "=================================================================="

# Set project/namespace
PROJECT_NAME="l1-app-ai"

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

# Check image registry access
echo "Checking image registry access..."
oc get is -n openshift || echo "WARNING: No access to OpenShift image streams"

# Test image pull capability
echo "Testing ClickHouse image pull capability..."
oc run test-clickhouse --image=clickhouse/clickhouse-server:23.8 --dry-run=server -o yaml

# Try alternative registry sources
echo "Checking alternative registries..."
echo "1. Docker Hub: clickhouse/clickhouse-server:23.8"
echo "2. Quay.io: quay.io/clickhouse/clickhouse-server:23.8"
echo "3. Red Hat Registry: registry.redhat.io (if available)"

# Apply the deployment
echo "Applying L1 Application deployment..."
oc apply -f openshift/l1-app-openshift-ai-deployment.yaml

# Check BuildConfig status
echo "Checking BuildConfig status..."
if oc get buildconfig/l1-app-ai-build -n $PROJECT_NAME >/dev/null 2>&1; then
    echo "BuildConfig found, checking build status..."
    oc get builds -n $PROJECT_NAME
    echo "Latest build logs:"
    LATEST_BUILD=$(oc get builds -n $PROJECT_NAME -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null)
    if [ ! -z "$LATEST_BUILD" ]; then
        oc logs build/$LATEST_BUILD -n $PROJECT_NAME --tail=20 || echo "No build logs available"
    fi
else
    echo "No BuildConfig found"
fi

# Test alternative image sources
echo "Testing image pull with alternative sources..."
echo "1. Testing Node.js base image:"
oc run test-node --image=node:18-alpine --dry-run=client -o yaml | head -10

# Check for image pull secrets
echo "Checking for image pull secrets..."
oc get secrets | grep -E "(pull|docker|registry)" || echo "No image pull secrets found"

# Wait for PVCs to be bound
echo "Waiting for PVCs to be bound..."
echo "ClickHouse PVC status:"
oc get pvc clickhouse-ai-pvc -n $PROJECT_NAME
echo "App Data PVC status:"
oc get pvc l1-app-ai-data-pvc -n $PROJECT_NAME

# Check pod status and events
echo "Checking pod status and events..."
sleep 30
oc get pods -n $PROJECT_NAME
echo ""
echo "Pod events for troubleshooting:"
oc get events --sort-by='.lastTimestamp' -n $PROJECT_NAME | tail -20

echo ""
echo "Troubleshooting Commands:"
echo "   - Check pod logs: oc logs deployment/clickhouse-ai -n $PROJECT_NAME"
echo "   - Describe pod: oc describe pod -l app=clickhouse-ai -n $PROJECT_NAME"
echo "   - Check events: oc get events --sort-by='.lastTimestamp' -n $PROJECT_NAME"
echo "   - Check image streams: oc get is -n $PROJECT_NAME"
echo ""
echo "Image Pull Issue Solutions:"
echo "1. Check network connectivity to Docker Hub"
echo "2. Verify cluster has access to external registries"
echo "3. Consider using internal OpenShift registry"
echo "4. Check if image pull secrets are required"
echo ""
echo "BuildConfig Issue Solutions:"
echo "1. Verify Git repository exists and is accessible"
echo "2. Check if Git repository requires authentication"
echo "3. Ensure Dockerfile exists in the repository"
echo "4. Consider using a different source strategy"
echo ""
echo "Quick Fixes:"
echo "   - Delete failed build: oc delete build --all -n $PROJECT_NAME"
echo "   - Start new build: oc start-build l1-app-ai-build -n $PROJECT_NAME"
echo "   - Use base image directly: oc patch deployment/l1-troubleshooting-ai -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"l1-app-ai\",\"image\":\"node:18-alpine\"}]}}}}' -n $PROJECT_NAME"
