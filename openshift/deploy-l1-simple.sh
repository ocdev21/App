
#!/bin/bash

echo "Deploying L1 Troubleshooting Application (Simple Version)"
echo "========================================================"

# Set project/namespace
PROJECT_NAME="l1-app-ns"

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

# Apply the simple deployment
echo "Applying L1 Application deployment..."
oc apply -f openshift/l1-app-simple-deployment.yaml

# Wait for PVCs to be bound
echo "Waiting for PVCs to be bound..."
oc wait --for=condition=Bound pvc/clickhouse-pvc -n $PROJECT_NAME --timeout=300s
oc wait --for=condition=Bound pvc/l1-app-data-pvc -n $PROJECT_NAME --timeout=300s

# Start build (if using BuildConfig)
echo "Starting application build..."
if oc get buildconfig/l1-app-build -n $PROJECT_NAME >/dev/null 2>&1; then
    oc start-build l1-app-build -n $PROJECT_NAME --wait
else
    echo "⚠️  BuildConfig not found, skipping build step"
fi

# Wait for ClickHouse deployment to be ready
echo "Waiting for ClickHouse deployment to be ready..."
oc rollout status deployment/clickhouse -n $PROJECT_NAME --timeout=600s

# Wait for L1 application deployment to be ready
echo "Waiting for L1 application deployment to be ready..."
oc rollout status deployment/l1-troubleshooting -n $PROJECT_NAME --timeout=600s

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
oc wait --for=condition=Ready pod -l app=l1-troubleshooting -n $PROJECT_NAME --timeout=300s
oc wait --for=condition=Ready pod -l app=clickhouse -n $PROJECT_NAME --timeout=300s

echo ""
echo "✅ L1 Application deployment completed successfully!"
echo ""
echo "📊 Application Information:"
echo "   - Namespace: $PROJECT_NAME"
echo "   - Application: l1-troubleshooting"
echo "   - Replicas: 2 (auto-scaling enabled: 2-5)"
echo ""
echo "🌐 Access Information:"
L1_ROUTE=$(oc get route l1-troubleshooting-route -n $PROJECT_NAME -o jsonpath='{.spec.host}' 2>/dev/null)
if [ ! -z "$L1_ROUTE" ]; then
    echo "   - Application URL: https://$L1_ROUTE"
    echo "   - 🎯 Click here to access your L1 Troubleshooting App: https://$L1_ROUTE"
else
    echo "   - Route not yet available, check: oc get route -n $PROJECT_NAME"
fi
echo ""
echo "🔍 Monitoring Commands:"
echo "   - Check pods: oc get pods -n $PROJECT_NAME"
echo "   - Check services: oc get svc -n $PROJECT_NAME"
echo "   - Check routes: oc get route -n $PROJECT_NAME"
echo "   - View app logs: oc logs deployment/l1-troubleshooting -n $PROJECT_NAME"
echo "   - View ClickHouse logs: oc logs deployment/clickhouse -n $PROJECT_NAME"
echo "   - Check HPA: oc get hpa -n $PROJECT_NAME"
echo "   - Check PVCs: oc get pvc -n $PROJECT_NAME"
echo ""
echo "🛠️  Management Commands:"
echo "   - Scale manually: oc scale deployment/l1-troubleshooting --replicas=X -n $PROJECT_NAME"
echo "   - Update config: oc edit configmap/l1-app-config -n $PROJECT_NAME"
echo "   - Restart deployment: oc rollout restart deployment/l1-troubleshooting -n $PROJECT_NAME"
echo ""
echo "📈 Features:"
echo "   - Auto-scaling: CPU and memory based (70%/80%)"
echo "   - Health checks: Configured"
echo "   - HTTPS: Enabled via OpenShift route"
echo "   - Database: ClickHouse for analytics"
echo ""
echo "🚀 Next Steps:"
echo "   1. Access your application at: https://$L1_ROUTE"
echo "   2. Upload files and test the troubleshooting features"
echo "   3. Monitor the application performance"
echo ""
echo "❓ Troubleshooting:"
echo "   - If app doesn't start: Check logs with 'oc logs deployment/l1-troubleshooting -n $PROJECT_NAME'"
echo "   - If ClickHouse issues: Check PVC binding and pod logs"
echo "   - If route issues: Check 'oc get route -n $PROJECT_NAME'"
