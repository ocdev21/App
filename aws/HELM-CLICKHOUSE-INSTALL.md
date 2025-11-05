# ClickHouse Installation Using Helm (Bitnami Chart)

## Prerequisites

**On your local machine (not Replit):**

1. **kubectl** configured for aws-hack cluster
2. **Helm 3.x** installed
3. **AWS EBS CSI driver** installed on aws-hack cluster

---

## Quick Installation Guide

Run these commands **on your local machine** with kubectl configured for the aws-hack cluster:

### Step 1: Add Bitnami Helm Repository

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Step 2: Create Namespace

```bash
kubectl create namespace l1-troubleshooting
```

### Step 3: Install ClickHouse

```bash
helm install clickhouse bitnami/clickhouse \
  --namespace l1-troubleshooting \
  --set auth.username=default \
  --set auth.password=foo \
  --set shards=1 \
  --set replicaCount=1 \
  --set zookeeper.enabled=false \
  --set keeper.enabled=true \
  --set persistence.enabled=true \
  --set persistence.storageClass=ebs-gp3 \
  --set persistence.size=50Gi \
  --set logsPersistence.enabled=true \
  --set logsPersistence.storageClass=ebs-gp3 \
  --set logsPersistence.size=10Gi \
  --set resources.requests.memory=2Gi \
  --set resources.requests.cpu=1000m \
  --set resources.limits.memory=4Gi \
  --set resources.limits.cpu=2000m \
  --wait \
  --timeout 10m
```

**Or use the values file:**

```bash
cd /path/to/l1-troubleshooting
helm install clickhouse bitnami/clickhouse \
  --namespace l1-troubleshooting \
  --values aws/helm/clickhouse-values.yaml \
  --wait \
  --timeout 10m
```

### Step 4: Verify Installation

```bash
# Check pod status
kubectl get pods -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse

# Check PVCs
kubectl get pvc -n l1-troubleshooting

# Check service
kubectl get svc -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse
```

### Step 5: Initialize Database

```bash
# Get pod name
CLICKHOUSE_POD=$(kubectl get pods -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')

# Create database
kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "CREATE DATABASE IF NOT EXISTS l1_troubleshooting"

# Create anomalies table
kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.anomalies (
    id String,
    timestamp DateTime,
    anomaly_type String,
    severity String,
    description String,
    source_file String,
    detection_method String,
    error_log String,
    packet_context String,
    confidence_score Float32,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, anomaly_type)
PARTITION BY toYYYYMM(timestamp)
"

# Create sessions table
kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.sessions (
    session_id String,
    file_name String,
    file_type String,
    start_time DateTime,
    end_time DateTime,
    packets_processed Int32,
    anomalies_detected Int32,
    status String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (start_time, session_id)
"

# Create metrics table
kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "
CREATE TABLE IF NOT EXISTS l1_troubleshooting.metrics (
    metric_name String,
    metric_value Float32,
    timestamp DateTime,
    tags Map(String, String),
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, metric_name)
PARTITION BY toYYYYMM(timestamp)
"

# Verify tables
kubectl exec -n l1-troubleshooting $CLICKHOUSE_POD -- clickhouse-client -u default --password foo --query "SHOW TABLES FROM l1_troubleshooting"
```

### Step 6: Apply NetworkPolicy (Security)

```bash
kubectl apply -f aws/kubernetes/clickhouse-networkpolicy.yaml
```

---

## Configuration Details

### Storage

- **Data Volume**: 50GB EBS gp3 SSD
- **Logs Volume**: 10GB EBS gp3 SSD
- **Storage Class**: ebs-gp3 (requires EBS CSI driver)

### Resources

- **Requests**: 2Gi memory, 1 CPU
- **Limits**: 4Gi memory, 2 CPU

### Authentication

- **Username**: `default`
- **Password**: `foo`

### Deployment Mode

- **Single-node** (1 shard, 1 replica)
- **ClickHouse Keeper** enabled (replaces ZooKeeper)

---

## Troubleshooting

### Pods Not Starting

Check pod events:
```bash
kubectl describe pod -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse
```

### PVCs Stuck in Pending

Check if EBS CSI driver is installed:
```bash
kubectl get pods -n kube-system | grep ebs-csi
```

If missing, install it:
```bash
# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM role
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster aws-hack \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-name AmazonEKS_EBS_CSI_DriverRole_aws_hack

# Install addon
aws eks create-addon \
  --cluster-name aws-hack \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole_aws_hack \
  --region us-east-1
```

### Check ClickHouse Logs

```bash
kubectl logs -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse -f
```

### Test Connection

```bash
CLICKHOUSE_POD=$(kubectl get pods -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n l1-troubleshooting -it $CLICKHOUSE_POD -- clickhouse-client -u default --password foo
```

---

## Uninstall ClickHouse

**WARNING: This will delete all data!**

```bash
# Uninstall Helm release
helm uninstall clickhouse -n l1-troubleshooting

# Delete PVCs (permanent data loss!)
kubectl delete pvc -n l1-troubleshooting -l app.kubernetes.io/name=clickhouse
```

---

## Upgrading ClickHouse

To upgrade to a newer version:

```bash
helm repo update
helm upgrade clickhouse bitnami/clickhouse \
  --namespace l1-troubleshooting \
  --values aws/helm/clickhouse-values.yaml \
  --wait
```

---

## Cost Estimate

### EBS Storage Costs (us-east-1)

- **Data volume**: 50GB gp3 @ $0.08/GB/month = **$4.00/month**
- **Logs volume**: 10GB gp3 @ $0.08/GB/month = **$0.80/month**
- **Total storage**: **~$5/month**

### Additional Costs

- **EC2 instance hours** (only when cluster running)
- **Data transfer** (negligible for internal cluster communication)

**Total ClickHouse cost**: **~$5/month** (storage only, assuming 4-hour weekly sessions)

---

## Next Steps

After ClickHouse is installed and running:

1. Deploy the L1 application pods
2. Configure the application to connect to ClickHouse service
3. Test anomaly detection and data storage
4. Monitor ClickHouse performance

For full deployment, see: `aws/QUICKSTART.md`
