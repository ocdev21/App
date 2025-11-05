# Deploy L1 Application to AWS EKS

## Prerequisites

✅ ClickHouse running in `l1-troubleshooting` namespace  
✅ Database schema initialized  
✅ Docker installed locally  
✅ AWS CLI configured  
✅ kubectl configured for `aws-hack` cluster  

## Quick Deploy

Run the automated deployment script:

```bash
chmod +x aws/scripts/deploy-l1-app.sh
./aws/scripts/deploy-l1-app.sh
```

This script will:
1. Create ECR repository for your Docker image
2. Build the Docker image (includes React frontend + Express backend + Bedrock inference server)
3. Push image to AWS ECR
4. Create IAM role with Bedrock permissions
5. Deploy application to EKS
6. Create LoadBalancer for external access
7. Display your application URL

**Estimated time**: 10-15 minutes

---

## What Gets Deployed

### Application Components

**Container Image**: Multi-service container with:
- **Port 5000**: React frontend + Express backend (user-facing web app)
- **Port 8000**: AWS Bedrock inference server (internal, calls Nova Pro)

### Environment Configuration

The deployment automatically configures:

| Variable | Value | Purpose |
|----------|-------|---------|
| `CLICKHOUSE_HOST` | `clickhouse.l1-troubleshooting.svc.cluster.local` | ClickHouse service DNS |
| `CLICKHOUSE_PORT` | `9000` | Native ClickHouse protocol port |
| `CLICKHOUSE_PASSWORD` | From secret `clickhouse-credentials` | Secure credential injection |
| `CLICKHOUSE_DATABASE` | `l1_troubleshooting` | Target database name |
| `TSLAM_REMOTE_HOST` | `localhost` | Bedrock server on same pod |
| `TSLAM_REMOTE_PORT` | `8000` | Bedrock inference API port |
| `AWS_REGION` | `us-east-1` | Bedrock API region |

### AWS Bedrock Integration

**IAM Role**: `L1BedrockRole` (IRSA - IAM Roles for Service Accounts)
- Attached to service account `l1-app-sa`
- Grants permission to invoke `amazon.nova-pro-v1:0`
- No API keys needed in code

**How it works**:
1. User clicks "Recommend" button in UI
2. Frontend sends request to Express backend `/ws` endpoint
3. Backend calls `http://localhost:8000/v1/chat/completions`
4. Bedrock inference server authenticates via IAM role
5. Calls AWS Bedrock Nova Pro model
6. Streams response back to frontend via WebSocket

---

## Post-Deployment

### Get Application URL

```bash
kubectl get svc l1-app-service -n l1-troubleshooting
```

Look for the `EXTERNAL-IP` (LoadBalancer hostname). Access your app at:
```
http://<EXTERNAL-IP>
```

### Verify ClickHouse Connection

```bash
# Check from pod
kubectl exec deployment/l1-app -n l1-troubleshooting -- \
  curl -s "http://clickhouse:9000/?query=SELECT%20version()"
```

### Verify Bedrock Access

```bash
# Check Bedrock health
kubectl exec deployment/l1-app -n l1-troubleshooting -- \
  curl -s http://localhost:8000/health
```

Should return:
```json
{
  "status": "healthy",
  "model": "amazon.nova-pro-v1:0",
  "region": "us-east-1"
}
```

### View Logs

```bash
# Application logs
kubectl logs -f deployment/l1-app -n l1-troubleshooting

# Filter for Bedrock activity
kubectl logs deployment/l1-app -n l1-troubleshooting | grep -i bedrock
```

---

## Testing the Application

### 1. Upload a PCAP File

1. Access the web UI via LoadBalancer URL
2. Upload a network capture file (`.pcap`, `.pcapng`, or `.dlf`)
3. System analyzes and stores anomalies in ClickHouse

### 2. View Anomalies

- Dashboard shows real-time metrics
- Anomalies table displays detected issues
- All data persists in ClickHouse (survives pod restarts)

### 3. Get AI Recommendations

1. Click "Recommend" button on any anomaly
2. Watch streaming AI analysis from AWS Bedrock Nova Pro
3. Recommendations display in popup window

---

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod -l app=l1-troubleshooting -n l1-troubleshooting
kubectl logs deployment/l1-app -n l1-troubleshooting
```

Common issues:
- Image pull errors → Check ECR permissions
- CrashLoopBackOff → Check logs for startup errors

### ClickHouse Connection Failed

```bash
# Test from pod
kubectl exec deployment/l1-app -n l1-troubleshooting -- \
  clickhouse-client -h clickhouse -u default --password defaultpass -q "SELECT 1"
```

### Bedrock Access Denied

Check IAM role is attached:
```bash
kubectl describe sa l1-app-sa -n l1-troubleshooting
```

Should show annotation:
```
eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/L1BedrockRole
```

### Enable Bedrock Model Access

If you get "Access Denied" for Bedrock:
1. Go to AWS Console → Bedrock → Model access
2. Request access to "Amazon Nova Pro"
3. Wait for approval (usually instant)

---

## Cleanup

To remove the deployment:

```bash
kubectl delete -f aws/kubernetes/l1-app-deployment.yaml

# Optional: Delete ECR repository
aws ecr delete-repository \
  --repository-name l1-troubleshooting \
  --region us-east-1 \
  --force
```

---

## Cost Estimate

Running 4-hour sessions:

| Resource | Cost |
|----------|------|
| EKS cluster | ~$0.10/hr |
| EC2 nodes (Auto Mode) | ~$0.20/hr |
| ClickHouse EFS | ~$0.33/GB/month |
| LoadBalancer | ~$0.025/hr |
| Bedrock Nova Pro | ~$0.008/1K tokens |
| **Total per 4hr session** | **~$2-3** |

Monthly with weekly 4hr sessions: **~$18-25/month**

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│  AWS EKS Cluster (aws-hack)                         │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │ Namespace: l1-troubleshooting                 │ │
│  │                                               │ │
│  │  ┌─────────────────┐    ┌──────────────────┐ │ │
│  │  │  L1 App Pod     │    │  ClickHouse Pod  │ │ │
│  │  │                 │    │                  │ │ │
│  │  │  ┌───────────┐  │    │  ┌────────────┐ │ │ │
│  │  │  │Port 5000  │◄─┼────┼──┤Port 9000   │ │ │ │
│  │  │  │Web App    │  │    │  │Native Proto│ │ │ │
│  │  │  └───────────┘  │    │  └────────────┘ │ │ │
│  │  │                 │    │         │        │ │ │
│  │  │  ┌───────────┐  │    │    ┌────▼─────┐ │ │ │
│  │  │  │Port 8000  │  │    │    │EFS Volume│ │ │ │
│  │  │  │Bedrock API│  │    │    │50GB Data │ │ │ │
│  │  │  └───────────┘  │    │    └──────────┘ │ │ │
│  │  │        │        │    └──────────────────┘ │ │
│  │  │        │IAM     │                          │ │
│  │  └────────┼────────┘                          │ │
│  │           │                                   │ │
│  │    ┌──────▼──────────┐                        │ │
│  │    │ Service Account │                        │ │
│  │    │  l1-app-sa      │                        │ │
│  │    └─────────────────┘                        │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  LoadBalancer Service                         │ │
│  │  Port 80 → 5000                               │ │
│  └───────────────────────────────────────────────┘ │
└──────────────────────────┬──────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  Internet   │
                    │  Clients    │
                    └─────────────┘

External Services:
┌─────────────────────┐
│  AWS Bedrock        │
│  amazon.nova-pro    │
│  (via IAM Role)     │
└─────────────────────┘
```

---

## Next Steps

After successful deployment:

1. **Test with sample PCAP files** from your network
2. **Monitor metrics** on the dashboard
3. **Try AI recommendations** to see Bedrock in action
4. **Scale up** if needed: `kubectl scale deployment/l1-app --replicas=2 -n l1-troubleshooting`
5. **Add custom domain** (optional) via Route 53 + LoadBalancer

---

**Questions?** Check the logs or contact support.
