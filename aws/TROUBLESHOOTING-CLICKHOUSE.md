# ClickHouse Deployment Troubleshooting Guide

## Common Issue: PVCs Stuck in "Pending" State

### Symptoms
- ClickHouse pod shows `ImagePullBackOff` or stays in `Pending` state
- PVCs (`clickhouse-data-clickhouse-0`, `clickhouse-logs-clickhouse-0`) stuck in "Waiting for a volume to be created"
- Error message: `failed to resolve image "docker.io/clickhouse/clickhouse-client:23.11-alpine": not found`

### Root Cause
The awshack EKS cluster is missing the **AWS EBS CSI driver** addon, which is required for dynamic provisioning of EBS volumes.

### Solution: Install EBS CSI Driver

**Step 1: Install the EBS CSI Driver**
```bash
cd aws/scripts
./install-ebs-csi-driver.sh
```

This script will:
- Detect your AWS account ID automatically
- Create IAM role with OIDC trust relationship
- Attach the AWS managed `AmazonEBSCSIDriverPolicy`
- Install the `aws-ebs-csi-driver` EKS addon
- Wait for the addon to become active

**Step 2: Clean Up Failed Deployment**
```bash
./cleanup-clickhouse.sh
```

This removes all ClickHouse resources (pods, PVCs, StatefulSet) to allow a clean redeployment.

**Step 3: Redeploy ClickHouse**
```bash
kubectl apply -f ../kubernetes/clickhouse-config.yaml
kubectl apply -f ../kubernetes/clickhouse-statefulset.yaml
kubectl apply -f ../kubernetes/clickhouse-networkpolicy.yaml
```

**Step 4: Verify Deployment**
```bash
# Check pod status (should show "Running" after 30-60 seconds)
kubectl get pods -n l1-troubleshooting -l app=clickhouse

# Check PVC status (should show "Bound")
kubectl get pvc -n l1-troubleshooting

# Check EBS volumes created
kubectl get pv
```

### Expected Timeline
- EBS CSI driver installation: **3-5 minutes**
- ClickHouse pod startup: **30-60 seconds**
- Database initialization: **10-20 seconds**

## Verification Steps

### 1. Check EBS CSI Driver Pods
```bash
kubectl get pods -n kube-system | grep ebs-csi
```

You should see:
```
ebs-csi-controller-xxxxx   6/6     Running
ebs-csi-node-xxxxx         3/3     Running
```

### 2. Test ClickHouse Connection
```bash
kubectl exec -n l1-troubleshooting -it clickhouse-0 -- clickhouse-client -u default --password foo --query "SELECT version()"
```

### 3. Verify Database Creation
```bash
kubectl exec -n l1-troubleshooting -it clickhouse-0 -- clickhouse-client -u default --password foo --query "SHOW DATABASES"
```

Should include `l1_troubleshooting` database.

### 4. Check Table Schema
```bash
kubectl exec -n l1-troubleshooting -it clickhouse-0 -- clickhouse-client -u default --password foo --database l1_troubleshooting --query "SHOW TABLES"
```

## Alternative: Using DynamoDB Instead

If you encounter persistent ClickHouse deployment issues or prefer a managed service, you can switch to DynamoDB:

### When to Use DynamoDB
- ✅ No persistent volume management needed
- ✅ Fully managed service (no pod restarts)
- ✅ Automatic scaling
- ✅ Lower operational complexity
- ❌ Higher cost for time-series queries
- ❌ Less optimized for analytics workloads

### Cost Comparison (4-hour weekly sessions)
| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| ClickHouse (EBS gp3 50GB) | ~$5/month | Storage only when cluster running |
| DynamoDB (on-demand) | ~$8-12/month | Pay per read/write requests |

### Switching to DynamoDB
1. Modify `server/db/storage.ts` to use DynamoDB client
2. Update anomaly detection scripts to write to DynamoDB
3. Remove ClickHouse StatefulSet from deployment
4. Update deployment scripts to skip ClickHouse setup

**Note:** The current architecture is optimized for ClickHouse's columnar storage and time-series analytics. DynamoDB would require query pattern adjustments.

## Debugging Commands

### View ClickHouse Logs
```bash
kubectl logs -n l1-troubleshooting clickhouse-0 -f
```

### Describe Pod (shows events)
```bash
kubectl describe pod clickhouse-0 -n l1-troubleshooting
```

### Check PVC Details
```bash
kubectl describe pvc clickhouse-data-clickhouse-0 -n l1-troubleshooting
```

### View EBS CSI Driver Logs
```bash
kubectl logs -n kube-system -l app=ebs-csi-controller
```

## Security Notes

- ClickHouse uses SHA256-hashed password authentication (default: `foo`)
- NetworkPolicy restricts access to app pods only
- IAM role uses OIDC federation (no static credentials)
- EBS volumes encrypted at rest by default

## Persistent Storage Details

### Volume Configuration
- **Data Volume**: 50GB gp3 SSD (`/var/lib/clickhouse`)
- **Logs Volume**: 10GB gp3 SSD (`/var/log/clickhouse-server`)
- **Storage Class**: `ebs-gp3` (3000 IOPS baseline)
- **Monthly Cost**: ~$5 (50GB data + 10GB logs)

### Backup Recommendations
For production use, configure:
1. EBS snapshots via AWS Backup
2. ClickHouse replication (multi-pod StatefulSet)
3. Regular database exports to S3

## Contact

For additional support, see:
- `aws/QUICKSTART.md` - Full deployment guide
- `aws/CLICKHOUSE-SECURITY.md` - Security hardening details
- `aws/COST-OPTIMIZATION.md` - Cost control strategies
