
#!/bin/bash

echo "Deploying L1 Troubleshooting Application to OpenShift AI Platform"
echo "================================================================="

# Set project/namespace for OpenShift AI
PROJECT_NAME="l1-app-ai"

# Check if OpenShift AI operator is installed
echo "Checking OpenShift AI installation..."
if ! oc get crd inferenceservices.serving.kserve.io >/dev/null 2>&1; then
    echo "❌ OpenShift AI (RHOAI) is not installed or KServe CRD not found"
    echo "Please ensure OpenShift AI operator is installed and configured"
    exit 1
fi

# Check if we have GPU nodes available
echo "Checking for GPU nodes..."
GPU_NODES=$(oc get nodes -l node.kubernetes.io/instance-type --no-headers | grep -c gpu || echo "0")
if [ "$GPU_NODES" -eq 0 ]; then
    echo "⚠️  Warning: No GPU nodes found. TSLAM model serving may not work optimally"
    echo "Consider adding GPU nodes or using CPU-only inference"
fi

# Create or switch to project
echo "Creating/switching to project: $PROJECT_NAME"
oc new-project $PROJECT_NAME 2>/dev/null || oc project $PROJECT_NAME

# Label namespace for OpenShift AI dashboard integration
echo "Configuring namespace for OpenShift AI integration..."
oc label namespace $PROJECT_NAME opendatahub.io/dashboard=true --overwrite

# Apply the complete OpenShift AI deployment
echo "Applying L1 Application deployment for OpenShift AI..."
oc apply -f openshift/l1-app-openshift-ai-deployment.yaml

# Wait for ClickHouse PVC to be bound
echo "Waiting for ClickHouse PVC to be bound..."
oc wait --for=condition=Bound pvc/clickhouse-ai-pvc -n $PROJECT_NAME --timeout=300s

# Wait for Application Data PVC to be bound
echo "Waiting for Application Data PVC to be bound..."
oc wait --for=condition=Bound pvc/l1-app-ai-data-pvc -n $PROJECT_NAME --timeout=300s

# Start build (if using BuildConfig)
echo "Starting application build..."
if oc get buildconfig/l1-app-ai-build -n $PROJECT_NAME >/dev/null 2>&1; then
    oc start-build l1-app-ai-build -n $PROJECT_NAME --wait
else
    echo "⚠️  BuildConfig not found, skipping build step"
fi

# Wait for ClickHouse deployment to be ready
echo "Waiting for ClickHouse deployment to be ready..."
oc rollout status deployment/clickhouse-ai -n $PROJECT_NAME --timeout=600s

# Wait for L1 application deployment to be ready
echo "Waiting for L1 application deployment to be ready..."
oc rollout status deployment/l1-troubleshooting-ai -n $PROJECT_NAME --timeout=600s

# Wait for model serving to be ready (if GPU available)
echo "Checking TSLAM model serving status..."
if oc get inferenceservice/tslam-model-serving -n $PROJECT_NAME >/dev/null 2>&1; then
    echo "TSLAM model serving found, waiting for ready status..."
    oc wait --for=condition=Ready inferenceservice/tslam-model-serving -n $PROJECT_NAME --timeout=900s
else
    echo "⚠️  TSLAM model serving not deployed, using remote fallback"
fi

# Wait for pods to be ready
echo "Waiting for all pods to be ready..."
oc wait --for=condition=Ready pod -l app=l1-troubleshooting-ai -n $PROJECT_NAME --timeout=300s
oc wait --for=condition=Ready pod -l app=clickhouse-ai -n $PROJECT_NAME --timeout=300s

echo ""
echo "✅ L1 Application deployment to OpenShift AI completed successfully!"
echo ""
echo "📊 Application Information:"
echo "   - Namespace: $PROJECT_NAME"
echo "   - Application: l1-troubleshooting-ai"
echo "   - Replicas: 2 (auto-scaling enabled: 2-10)"
echo "   - Platform: OpenShift AI (RHOAI)"
echo ""
echo "🌐 Access Information:"
L1_ROUTE=$(oc get route l1-troubleshooting-ai-route -n $PROJECT_NAME -o jsonpath='{.spec.host}' 2>/dev/null)
if [ ! -z "$L1_ROUTE" ]; then
    echo "   - Application URL: https://$L1_ROUTE"
    echo "   - 🎯 Click here to access your L1 Troubleshooting App: https://$L1_ROUTE"
else
    echo "   - Route not yet available, check: oc get route -n $PROJECT_NAME"
fi
echo ""
echo "🤖 AI Services Information:"
TSLAM_ENDPOINT=$(oc get inferenceservice/tslam-model-serving -n $PROJECT_NAME -o jsonpath='{.status.url}' 2>/dev/null)
if [ ! -z "$TSLAM_ENDPOINT" ]; then
    echo "   - TSLAM Model Serving: $TSLAM_ENDPOINT"
else
    echo "   - TSLAM Model Serving: Using remote fallback (10.193.0.4:8080)"
fi
echo "   - ClickHouse Analytics: Internal cluster service"
echo ""
echo "🔍 Monitoring Commands:"
echo "   - Check pods: oc get pods -n $PROJECT_NAME"
echo "   - Check services: oc get svc -n $PROJECT_NAME"
echo "   - Check routes: oc get route -n $PROJECT_NAME"
echo "   - Check model serving: oc get inferenceservice -n $PROJECT_NAME"
echo "   - View app logs: oc logs deployment/l1-troubleshooting-ai -n $PROJECT_NAME"
echo "   - View ClickHouse logs: oc logs deployment/clickhouse-ai -n $PROJECT_NAME"
echo "   - Check HPA: oc get hpa -n $PROJECT_NAME"
echo ""
echo "🛠️  Management Commands:"
echo "   - Scale manually: oc scale deployment/l1-troubleshooting-ai --replicas=X -n $PROJECT_NAME"
echo "   - Update config: oc edit configmap/l1-app-ai-config -n $PROJECT_NAME"
echo "   - Restart deployment: oc rollout restart deployment/l1-troubleshooting-ai -n $PROJECT_NAME"
echo "   - Access OpenShift AI dashboard: Check your OpenShift AI console"
echo ""
echo "📈 OpenShift AI Features:"
echo "   - Model Serving: KServe-based TSLAM inference"
echo "   - Auto-scaling: CPU and memory based (70%/80%)"
echo "   - GPU Acceleration: Available for model inference"
echo "   - Dashboard Integration: Visible in RHOAI dashboard"
echo "   - Network Policies: Configured for AI workloads"
echo ""
echo "🚀 Next Steps:"
echo "   1. Access your application at: https://$L1_ROUTE"
echo "   2. Check OpenShift AI dashboard for model serving status"
echo "   3. Upload files and test anomaly detection features"
echo "   4. Monitor GPU usage if using model serving"
echo ""
echo "❓ Troubleshooting:"
echo "   - If model serving fails: Check GPU node availability"
echo "   - If app doesn't start: Check logs with 'oc logs deployment/l1-troubleshooting-ai -n $PROJECT_NAME'"
echo "   - If ClickHouse issues: Check PVC binding and pod logs"
