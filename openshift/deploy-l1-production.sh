
#!/bin/bash

echo "Deploying L1 Troubleshooting Application to Production"
echo "====================================================="

# Set project/namespace
PROJECT_NAME="l1-app"

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

# Apply the complete deployment
echo "Applying L1 Application deployment..."
oc apply -f openshift/l1-app-production-deployment.yaml

# Wait for build to complete (if using BuildConfig)
echo "Waiting for build to complete..."
oc start-build l1-app-build -n $PROJECT_NAME --wait

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
oc rollout status deployment/l1-troubleshooting -n $PROJECT_NAME --timeout=600s

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
oc wait --for=condition=Ready pod -l app=l1-troubleshooting -n $PROJECT_NAME --timeout=300s

echo ""
echo "L1 Application deployment completed successfully!"
echo ""
echo "Application Information:"
echo "   - Namespace: $PROJECT_NAME"
echo "   - Application: l1-troubleshooting"
echo "   - Replicas: 2 (auto-scaling enabled: 2-10)"
echo ""
echo "Access Information:"
L1_ROUTE=$(oc get route l1-troubleshooting-route -n $PROJECT_NAME -o jsonpath='{.spec.host}' 2>/dev/null)
if [ ! -z "$L1_ROUTE" ]; then
    echo "   - Application URL: https://$L1_ROUTE"
else
    echo "   - Route not yet available, check: oc get route -n $PROJECT_NAME"
fi
echo ""
echo "Monitoring Commands:"
echo "   - Check pods: oc get pods -n $PROJECT_NAME"
echo "   - Check services: oc get svc -n $PROJECT_NAME"
echo "   - Check routes: oc get route -n $PROJECT_NAME"
echo "   - View logs: oc logs deployment/l1-troubleshooting -n $PROJECT_NAME"
echo "   - Check HPA: oc get hpa -n $PROJECT_NAME"
echo ""
echo "Management Commands:"
echo "   - Scale manually: oc scale deployment/l1-troubleshooting --replicas=X -n $PROJECT_NAME"
echo "   - Update config: oc edit configmap/l1-app-config -n $PROJECT_NAME"
echo "   - Restart deployment: oc rollout restart deployment/l1-troubleshooting -n $PROJECT_NAME"
echo ""
echo "Performance Features:"
echo "   - Auto-scaling: Enabled (CPU: 70%, Memory: 80%)"
echo "   - Session affinity: Enabled"
echo "   - Health checks: Configured"
echo "   - Network policies: Applied"
