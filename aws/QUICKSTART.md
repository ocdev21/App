# Quick Start Guide - AWS EKS Deployment

Complete setup from scratch in **30 minutes**.

## Prerequisites

✅ EC2 instance running (t3.medium or larger)  
✅ AWS CLI configured (`aws configure`)  
✅ Docker installed  
✅ kubectl installed  
✅ Helm installed  
✅ Code uploaded to EC2 instance  

---

## Step-by-Step Setup

### 1️⃣ Create EKS Cluster (20-25 minutes)

```bash
cd ~/l1-troubleshooting/aws/scripts
./setup-eks-cluster.sh l1-troubleshooting-cluster us-east-1
```

**What this does:**
- ✅ Creates EKS cluster with 2 t3.medium nodes
- ✅ Installs AWS Load Balancer Controller
- ✅ Installs EBS CSI driver (for ClickHouse)
- ✅ Installs EFS CSI driver (for app files)
- ✅ Configures kubectl

**Wait for completion** (~20-25 minutes)

---

### 2️⃣ Build and Push Docker Image (3-5 minutes)

```bash
# Get your AWS account ID
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Build and push
./build-and-push.sh $AWS_ACCOUNT us-east-1
```

**What this does:**
- ✅ Creates ECR repository
- ✅ Builds Docker image with Bedrock integration
- ✅ Pushes to ECR

---

### 3️⃣ Create Bedrock IAM Role (1 minute)

```bash
eksctl create iamserviceaccount \
  --name bedrock-access-sa \
  --namespace l1-troubleshooting \
  --cluster l1-troubleshooting-cluster \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess \
  --approve \
  --override-existing-serviceaccounts
```

**What this does:**
- ✅ Creates Kubernetes ServiceAccount with IAM role
- ✅ Grants Bedrock Nova Pro access via IRSA

---

### 4️⃣ Create EFS Filesystem (2 minutes)

```bash
# Get VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name l1-troubleshooting-cluster \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

# Create EFS
EFS_ID=$(aws efs create-file-system \
  --region us-east-1 \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value=l1-troubleshooting-efs \
  --query 'FileSystemId' \
  --output text)

echo "EFS created: $EFS_ID"

# Get subnet IDs
SUBNET_IDS=$(aws eks describe-cluster \
  --name l1-troubleshooting-cluster \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.subnetIds' \
  --output text)

# Create security group for EFS
SG_ID=$(aws ec2 create-security-group \
  --group-name l1-efs-sg \
  --description "Security group for L1 EFS" \
  --vpc-id $VPC_ID \
  --region us-east-1 \
  --query 'GroupId' \
  --output text)

# Allow NFS traffic from VPC
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr 10.0.0.0/8 \
  --region us-east-1

# Create mount targets
for SUBNET in $SUBNET_IDS; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $SUBNET \
    --security-groups $SG_ID \
    --region us-east-1 2>/dev/null || echo "Mount target may already exist"
done

# Update StorageClass with EFS ID
sed -i "s/fileSystemId: .*/fileSystemId: $EFS_ID/" ../kubernetes/storageclass-efs.yaml

echo "✅ EFS ready: $EFS_ID"
```

---

### 5️⃣ Update Deployment Configuration (1 minute)

```bash
# Update ECR image reference in deployment.yaml
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
sed -i "s|image: .*l1-integrated.*|image: ${AWS_ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/l1-integrated:latest|" \
  ../kubernetes/deployment.yaml
```

---

### 6️⃣ Deploy Application + ClickHouse (5 minutes)

```bash
./deploy.sh l1-troubleshooting-cluster us-east-1
```

**What this does:**
- ✅ Creates namespace and storage
- ✅ Deploys ClickHouse with EBS volumes
- ✅ Initializes database and tables
- ✅ Deploys application pods
- ✅ Creates LoadBalancer service

---

### 7️⃣ Get Application URL (1 minute)

```bash
# Wait for LoadBalancer
kubectl get ingress -n l1-troubleshooting -w
# Press Ctrl+C after ADDRESS appears

# Or get LoadBalancer directly
kubectl get svc l1-service -n l1-troubleshooting
```

Access your application at: `http://<EXTERNAL-IP>:5000`

---

## ✅ Verification Checklist

```bash
# Check all pods running
kubectl get pods -n l1-troubleshooting

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# clickhouse-0                    1/1     Running   0          5m
# l1-integrated-xxxxxxxxxx-xxxxx  1/1     Running   0          3m
# l1-integrated-xxxxxxxxxx-xxxxx  1/1     Running   0          3m

# Check ClickHouse
kubectl exec -it clickhouse-0 -n l1-troubleshooting -- \
  clickhouse-client --password foo -q "SHOW DATABASES"

# Expected: l1_troubleshooting

# Check application logs
kubectl logs -n l1-troubleshooting -l app=l1-integrated --tail=50
```

---

## 🛑 Stop After Session (Save Money!)

```bash
cd ~/l1-troubleshooting/aws/scripts

# Full stop (recommended for weekly usage)
./stop-all-services.sh full

# Cost when stopped: ~$5/month (EBS only)
```

---

## 🚀 Start for Next Session

```bash
cd ~/l1-troubleshooting/aws/scripts

# Quick start (5 minutes)
./start-all-services.sh quick
```

---

## 💰 Monthly Cost Breakdown

| Component | Cost (4hr weekly) |
|-----------|------------------|
| EKS Control Plane | ~$3/month |
| EC2 Nodes (4hr/week) | ~$7/month |
| EBS (ClickHouse) | ~$5/month |
| EFS (App files) | ~$2/month |
| ALB | ~$1/month |
| **Total** | **~$18/month** ✅ |

---

## 🚨 Troubleshooting

**Cluster creation fails:**
```bash
# Check AWS limits
aws service-quotas list-service-quotas \
  --service-code eks --region us-east-1

# Check IAM permissions
aws sts get-caller-identity
```

**Pods stuck in Pending:**
```bash
# Check node capacity
kubectl describe nodes

# Check events
kubectl get events -n l1-troubleshooting --sort-by='.lastTimestamp'
```

**ClickHouse won't start:**
```bash
# Check logs
kubectl logs clickhouse-0 -n l1-troubleshooting

# Check PVC
kubectl get pvc -n l1-troubleshooting

# Check storage class
kubectl get storageclass
```

**Can't access application:**
```bash
# Check service
kubectl get svc -n l1-troubleshooting

# Check ingress
kubectl describe ingress -n l1-troubleshooting

# Check LoadBalancer
kubectl get svc l1-service -n l1-troubleshooting -o wide
```

---

## 📚 Additional Resources

- **Cost Control**: See `COST-CONTROL-GUIDE.md`
- **ClickHouse Security**: See `CLICKHOUSE-SECURITY.md`
- **Full Documentation**: See `README.md`
- **EC2 Setup**: See `EC2-SETUP-GUIDE.md`
