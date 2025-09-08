
#!/bin/bash

echo "Deploying L1 Troubleshooting Application to Kubernetes"
echo "====================================================="

NAMESPACE="l1-app-ai"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is required but not installed."
    exit 1
fi

echo "🚀 Starting L1 Application deployment..."

# Step 1: Create application code ConfigMap
echo "Step 1: Creating application code ConfigMap..."
chmod +x create-app-configmap.sh
./create-app-configmap.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to create application ConfigMap"
    exit 1
fi

# Step 2: Deploy the L1 application
echo "Step 2: Deploying L1 application..."
kubectl apply -f k8s-l1-app-deployment.yaml

if [ $? -ne 0 ]; then
    echo "❌ Failed to deploy L1 application"
    exit 1
fi

# Step 3: Wait for PVCs to be bound
echo "Step 3: Waiting for PVCs to be bound..."
kubectl wait --for=condition=Bound pvc/l1-app-data-pvc -n $NAMESPACE --timeout=300s

# Step 4: Wait for deployment to be ready
echo "Step 4: Waiting for deployment to be ready..."
kubectl rollout status deployment/l1-troubleshooting -n $NAMESPACE --timeout=600s

# Step 5: Wait for pods to be ready
echo "Step 5: Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=l1-troubleshooting -n $NAMESPACE --timeout=600s

# Step 6: Show deployment status
echo "Step 6: Checking deployment status..."
echo ""
echo "🔍 Deployment Status:"
kubectl get all -n $NAMESPACE

echo ""
echo "📊 Pod Details:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "🌐 Service Information:"
kubectl get svc -n $NAMESPACE

echo ""
echo "💾 Storage Information:"
kubectl get pvc -n $NAMESPACE

# Test ClickHouse connectivity from the application
echo ""
echo "🔗 Testing ClickHouse connectivity..."
APP_POD=$(kubectl get pods -n $NAMESPACE -l app=l1-troubleshooting -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$APP_POD" ]; then
    echo "Testing from pod: $APP_POD"
    kubectl exec -n $NAMESPACE $APP_POD -- sh -c 'curl -s http://chi-clickhouse-single-clickhouse-0-0.l1-app-ai.svc.cluster.local:8123/ping || echo "ClickHouse not reachable"'
else
    echo "No application pod found for connectivity test"
fi

echo ""
echo "🎉 L1 Application deployment completed!"
echo ""
echo "📋 Quick Commands:"
echo "   Check status: kubectl get all -n $NAMESPACE"
echo "   View logs: kubectl logs deployment/l1-troubleshooting -n $NAMESPACE"
echo "   Port forward: kubectl port-forward svc/l1-troubleshooting-service 8080:80 -n $NAMESPACE"
echo "   Scale app: kubectl scale deployment/l1-troubleshooting --replicas=3 -n $NAMESPACE"
echo ""
echo "🔧 Configuration:"
echo "   - Namespace: $NAMESPACE"
echo "   - Application Service: l1-troubleshooting-service"
echo "   - HTTP Port: 80 (mapped to 5000)"
echo "   - Auto-scaling: 2-5 replicas"
echo "   - ClickHouse: chi-clickhouse-single-clickhouse-0-0"
echo "   - Database: l1_anomaly_detection"
