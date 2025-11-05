# L1 Application - Quick Deploy to EKS

Your ClickHouse database is ready. Deploy your L1 application in 3 commands:

## Prerequisites Check

```bash
# Verify ClickHouse is running
kubectl get pods -n l1-troubleshooting | grep clickhouse
# Should show: clickhouse-shard0-0   1/1   Running

# Verify database is initialized
kubectl get secret clickhouse-credentials -n l1-troubleshooting
# Should exist
```

## Deploy Application

### Step 1: Enable AWS Bedrock Model Access

Before deployment, enable access to Amazon Nova Pro:

1. Go to [AWS Console → Bedrock → Model access](https://console.aws.amazon.com/bedrock/home#/modelaccess)
2. Click "Request model access"
3. Select "Amazon Nova Pro"
4. Submit request (approval is instant)

### Step 2: Run Deployment Script

```bash
chmod +x aws/scripts/deploy-l1-app.sh
./aws/scripts/deploy-l1-app.sh
```

This takes **10-15 minutes** and will:
- Build Docker image with your app + Bedrock server
- Push to AWS ECR
- Create IAM role for Bedrock access
- Deploy to EKS with LoadBalancer
- Display your application URL

### Step 3: Access Your Application

After deployment completes, you'll see:

```
✅ Deployment Complete!
Application URL: http://abc123-xxx.us-east-1.elb.amazonaws.com
```

Open that URL in your browser!

---

## What You Get

**Frontend**: React UI at port 80 (via LoadBalancer)

**Backend**: 
- Express API connected to ClickHouse for anomaly storage
- AWS Bedrock Nova Pro for AI recommendations (no local model needed)

**Database**: 
- ClickHouse with 50GB persistent EFS storage
- Survives pod restarts

---

## Testing the System

1. **Upload a network capture file** (PCAP, DLF, or QXDM)
2. **View detected anomalies** on the dashboard (stored in ClickHouse)
3. **Click "Recommend"** on any anomaly → streams AI analysis from AWS Bedrock

---

## Verify Everything Works

```bash
# Check pods are running
kubectl get pods -n l1-troubleshooting

# View application logs
kubectl logs -f deployment/l1-app -n l1-troubleshooting

# Test ClickHouse connection
kubectl exec deployment/l1-app -n l1-troubleshooting -- \
  curl -s "http://clickhouse:9000/?query=SELECT%20version()"

# Test Bedrock health
kubectl exec deployment/l1-app -n l1-troubleshooting -- \
  curl -s http://localhost:8000/health
```

---

## Cost

Running 4-hour sessions weekly: **~$18-25/month**

To stop and save costs:
```bash
kubectl scale deployment/l1-app --replicas=0 -n l1-troubleshooting
kubectl scale statefulset/clickhouse --replicas=0 -n l1-troubleshooting
```

---

## Full Documentation

See `aws/DEPLOY-TO-EKS.md` for:
- Architecture details
- Troubleshooting guide
- Configuration options
- Cost breakdown

---

**That's it!** Your L1 troubleshooting system with ClickHouse and AWS Bedrock is ready to use.
