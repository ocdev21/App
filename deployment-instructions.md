# L1 Network Troubleshooting System - OpenShift Deployment Guide

## 🚀 Complete Deployment Instructions

### Prerequisites
- OpenShift cluster access
- Docker/Podman for building images
- `oc` CLI tool installed and configured
- Access to OpenShift image registry

### Step 1: Build the Production Docker Image

```bash
# Build the production image with all AI/ML and npm packages
docker build -f Dockerfile.production -t l1-app-production:latest .

# Verify the image was built successfully
docker images | grep l1-app-production
```

### Step 2: Tag and Push to OpenShift Registry

```bash
# Login to OpenShift registry
oc registry login

# Get the registry URL
REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

# Tag the image for OpenShift registry
docker tag l1-app-production:latest $REGISTRY/l1-app-ai/l1-app-production:latest

# Push to OpenShift registry
docker push $REGISTRY/l1-app-ai/l1-app-production:latest
```

### Step 3: Create the Namespace (if not exists)

```bash
# Create the l1-app-ai namespace
oc new-project l1-app-ai || oc project l1-app-ai
```

### Step 4: Deploy the Application

```bash
# Apply the deployment configuration
oc apply -f k8s-l1-deployment.yaml

# Verify deployment status
oc get deployments -n l1-app-ai
oc get pods -n l1-app-ai
oc get services -n l1-app-ai
oc get routes -n l1-app-ai
```

### Step 5: Access the Application

```bash
# Get the external URL
oc get route l1-troubleshooting-route -n l1-app-ai -o jsonpath='{.spec.host}'

# Open in browser
echo "Application URL: http://$(oc get route l1-troubleshooting-route -n l1-app-ai -o jsonpath='{.spec.host}')"
```

## 🔍 Monitoring and Troubleshooting

### Check Pod Logs
```bash
# View application logs
oc logs -f deployment/l1-troubleshooting-app -n l1-app-ai

# View specific pod logs
oc logs <pod-name> -n l1-app-ai
```

### Check Pod Status
```bash
# Get detailed pod information
oc describe pod <pod-name> -n l1-app-ai

# Check resource usage
oc top pods -n l1-app-ai
```

### Scale the Application
```bash
# Scale up/down replicas
oc scale deployment l1-troubleshooting-app --replicas=3 -n l1-app-ai
```

## 🛠️ Configuration Options

### Environment Variables
The deployment includes these key environment variables:
- `NODE_ENV=production`
- `PORT=5000`
- `PYTHONPATH=/app`
- `OMP_NUM_THREADS=4` (AI/ML optimization)
- `MKL_NUM_THREADS=4` (AI/ML optimization)

### Resource Limits
- **Memory**: 2Gi request, 8Gi limit
- **CPU**: 1000m request, 4000m limit
- **Cache Volume**: 2Gi for AI model caching

### Health Checks
- **Readiness Probe**: Checks if app is ready to receive traffic
- **Liveness Probe**: Restarts unhealthy containers

## 🔧 Advanced Operations

### Update Deployment
```bash
# Update image version
oc set image deployment/l1-troubleshooting-app l1-app=l1-app-production:v2.0 -n l1-app-ai

# Rollback if needed
oc rollout undo deployment/l1-troubleshooting-app -n l1-app-ai
```

### Port Forward for Local Access
```bash
# Port forward for local testing
oc port-forward svc/l1-troubleshooting-service 8080:80 -n l1-app-ai
# Access at: http://localhost:8080
```

### Clean Up
```bash
# Remove all resources
oc delete -f k8s-l1-deployment.yaml

# Delete namespace (optional)
oc delete project l1-app-ai
```

## 📊 Expected Features After Deployment

✅ **AI-Powered Anomaly Detection** - Real-time network analysis  
✅ **TSLAM-4B Model Integration** - Advanced AI recommendations  
✅ **Dashboard Interface** - Interactive network troubleshooting  
✅ **Real-time Analytics** - Live metrics and visualization  
✅ **High Availability** - Multi-replica deployment  
✅ **Auto-scaling Ready** - Resource-optimized containers  

## 🎯 Success Indicators

1. **Pods Running**: All pods show "Running" status
2. **Route Accessible**: External URL responds with 200 OK
3. **AI Models Loading**: Check logs for successful model initialization
4. **Frontend Rendering**: Dashboard loads with network metrics
5. **API Endpoints Working**: REST API responds to requests

Your L1 Network Troubleshooting System with complete AI/ML stack is now ready for production use! 🚀