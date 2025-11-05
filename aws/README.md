# L1 Troubleshooting System - AWS EKS Deployment

Complete deployment guide for running the L1 Network Troubleshooting System on Amazon EKS.

## Architecture Overview

**Components:**
- **Web Application**: React frontend + Express backend (Port 5000)
- **AI Inference**: Amazon Bedrock (Nova Pro) for streaming AI recommendations
- **ML Analyzer**: Python-based anomaly detection for PCAP/DLF/QXDM files
- **Databases**: ClickHouse for anomaly storage, PostgreSQL for metadata
- **Storage**: Amazon EFS for shared files, EBS for database persistence

**AWS Services Used:**
- Amazon EKS (Kubernetes cluster)
- Amazon ECR (Container registry)
- **Amazon Bedrock** (AI inference with Nova Pro model)
- Amazon EFS (Shared file storage for network captures)
- Amazon EBS (Block storage for databases)
- AWS Load Balancer Controller (ALB for ingress)
- AWS Certificate Manager (SSL/TLS certificates)
- Amazon RDS (Optional managed PostgreSQL)

## Prerequisites

### 1. AWS CLI & kubectl
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### 2. Create EKS Cluster

Using `eksctl`:
```bash
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Create EKS cluster
eksctl create cluster \
  --name l1-troubleshooting-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.xlarge \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 10 \
  --managed
```

### 3. Install AWS Load Balancer Controller

```bash
# Create IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# Create IAM service account
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=l1-troubleshooting-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# Install controller via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=l1-troubleshooting-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 4. Install EFS CSI Driver

```bash
# Create IAM policy for EFS CSI driver
curl -o efs-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json

aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
    --policy-document file://efs-iam-policy.json

# Create service account
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
    --cluster l1-troubleshooting-cluster \
    --namespace kube-system \
    --name efs-csi-controller-sa \
    --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve

# Install EFS CSI driver
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa
```

### 5. Create EFS File System

```bash
# Get VPC ID and Subnet IDs from EKS cluster
VPC_ID=$(aws eks describe-cluster --name l1-troubleshooting-cluster --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Create EFS file system
aws efs create-file-system \
    --region us-east-1 \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --encrypted \
    --tags Key=Name,Value=l1-troubleshooting-efs

# Get the File System ID
EFS_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='l1-troubleshooting-efs'].FileSystemId" --output text)

# Create mount targets in each subnet
# (Repeat for each subnet in your EKS cluster)
aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id <SUBNET_ID> \
    --security-groups <SECURITY_GROUP_ID>
```

## Deployment Steps

### Step 1: Build and Push Docker Image to ECR

```bash
cd aws/scripts
chmod +x build-and-push.sh

# Build and push image
./build-and-push.sh <AWS_ACCOUNT_ID> <AWS_REGION> <IMAGE_TAG>

# Example:
./build-and-push.sh 123456789012 us-east-1 v1.0.0
```

### Step 2: Update Configuration Files

#### Update `kubernetes/storageclass-efs.yaml`
```yaml
parameters:
  fileSystemId: fs-xxxxxxxxx  # Your EFS File System ID
```

#### Update `kubernetes/deployment.yaml`
```yaml
image: <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/l1-integrated:latest
```

#### Update `kubernetes/ingress.yaml`
```yaml
annotations:
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:<REGION>:<ACCOUNT>:certificate/<CERT_ID>

spec:
  rules:
    - host: l1-troubleshooting.yourdomain.com  # Your domain
```

#### Update `kubernetes/secrets.yaml`
```bash
# Create secrets using kubectl instead of storing in Git
kubectl create secret generic l1-app-secrets \
  --from-literal=CLICKHOUSE_PASSWORD='your-password' \
  --from-literal=PGPASSWORD='your-postgres-password' \
  -n l1-troubleshooting
```

### Step 3: Configure Amazon Bedrock Access

**Enable Bedrock Model Access:**
1. Go to AWS Console → Amazon Bedrock → Model access
2. Click "Manage model access"
3. Enable **Amazon Nova Pro** (`amazon.nova-pro-v1:0`)
4. Submit the request (usually approved instantly)

**Create IAM Role for Bedrock Access (IRSA):**

**IMPORTANT**: This step must be completed BEFORE running deploy.sh. The eksctl command creates the service account with proper IAM role binding.

```bash
# Enable OIDC provider for your EKS cluster (if not already enabled)
eksctl utils associate-iam-oidc-provider \
  --cluster l1-troubleshooting-cluster \
  --region us-east-1 \
  --approve

# Create IAM policy for Bedrock from the provided policy file
# Navigate to aws/ directory first
cd kubernetes
aws iam create-policy \
  --policy-name L1BedrockAccessPolicy \
  --policy-document file://bedrock-policy.json

# Create IAM service account with Bedrock permissions
# This command creates the ServiceAccount AND binds it to the IAM role
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --name l1-bedrock-sa \
  --namespace l1-troubleshooting \
  --cluster l1-troubleshooting-cluster \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/L1BedrockAccessPolicy \
  --approve \
  --override-existing-serviceaccounts
```

**Important Notes:**
- Account ID: Get dynamically via `aws sts get-caller-identity --query Account --output text`
- The `bedrock-iam-role.yaml` file is provided for reference only
- Do NOT manually apply `bedrock-iam-role.yaml` as it contains placeholder values
- Always use eksctl to create/update the service account to ensure proper IRSA configuration

### Step 4: Deploy to EKS

```bash
cd aws/scripts
chmod +x deploy.sh

# Deploy all resources
./deploy.sh l1-troubleshooting-cluster us-east-1
```

### Step 5: Get ALB URL

```bash
# Wait for ALB to be provisioned (may take 2-3 minutes)
kubectl get ingress l1-integrated-ingress -n l1-troubleshooting -w

# Get the ALB DNS name
ALB_URL=$(kubectl get ingress l1-integrated-ingress -n l1-troubleshooting -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Access your application at: https://$ALB_URL"
```

### Step 6: Configure DNS (Optional)

Point your domain to the ALB:
```bash
# Create Route53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "l1-troubleshooting.yourdomain.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$ALB_URL'"}]
      }
    }]
  }'
```

## ClickHouse in EKS

### Architecture

ClickHouse runs as a **StatefulSet** in your EKS cluster with the following setup:
- **Pod**: `clickhouse-0` (single replica for 4-hour usage)
- **Service**: `clickhouse.l1-troubleshooting.svc.cluster.local`
- **Storage**: **EBS gp3 volumes** (50GB data + 10GB logs) - ClickHouse requires low-latency block storage
- **Database**: `l1_troubleshooting` with optimized tables
- **Memory**: Configured for 2GB max usage (fits within 4Gi pod limit)
- **Security**: Network restricted to VPC (10.0.0.0/8)

### Tables Created

1. **anomalies**: Stores all detected L1 anomalies
   - Partitioned by month (`toYYYYMM(timestamp)`)
   - Ordered by timestamp, type, severity
   - Includes packet context and confidence scores

2. **metrics**: System and network metrics
   - Time-series optimized
   - Auto-partitioned for efficient queries

3. **sessions**: Analysis session tracking
   - Tracks files processed and anomalies detected

### Connection Details

The application automatically connects using these environment variables:
```bash
CLICKHOUSE_HOST=clickhouse-0.clickhouse.l1-troubleshooting.svc.cluster.local
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=l1_troubleshooting
CLICKHOUSE_USERNAME=default
CLICKHOUSE_PASSWORD=<from-secret>  # Stored in l1-app-secrets
```

**Security Configuration**:
1. **Password Authentication**: Required for all connections (default password: "foo" - **CHANGE IN PRODUCTION!**)
2. **Network Isolation**: 
   - NetworkPolicy restricts access to only `l1-integrated` application pods
   - ClickHouse user restricted to VPC range (10.0.0.0/8)
3. **Changing Password**:
   ```bash
   # Generate SHA256 hash
   echo -n 'your-new-password' | sha256sum
   
   # Update clickhouse-config.yaml with the hash
   # Update secrets.yaml with the plaintext password
   # Redeploy: kubectl apply -f ../kubernetes/clickhouse-config.yaml
   # Restart pod: kubectl delete pod clickhouse-0 -n l1-troubleshooting
   ```

### Manual Access

```bash
# Access ClickHouse client
kubectl exec -it clickhouse-0 -n l1-troubleshooting -- clickhouse-client

# Query anomalies
SELECT type, count(*) as count, avg(confidence_score) as avg_confidence
FROM l1_troubleshooting.anomalies
GROUP BY type
ORDER BY count DESC;

# Check database size
SELECT
    database,
    formatReadableSize(sum(bytes)) as size
FROM system.parts
WHERE database = 'l1_troubleshooting'
GROUP BY database;
```

### Data Persistence

- ClickHouse data survives pod restarts
- **Stored on EBS gp3 volumes** (required for performance and data integrity)
- **Important**: EBS volumes are zone-specific and persist when pods are stopped
- Automatic monthly partitioning for old data cleanup
- Estimated storage growth: ~1-5GB per month of usage
- **Note**: EBS volumes remain provisioned even when cluster is stopped (see cost impact below)

### Cost Impact

For 4-hour weekly sessions:
- **No additional compute cost** (uses existing EKS nodes)
- **EBS Storage cost** (60GB total, persists even when stopped):
  - gp3 volumes: ~$4.80/month (always charged)
  - **IMPORTANT**: Unlike EFS, EBS volumes are NOT deleted with quick/full stop
- **Total ongoing cost**: ~$5/month for ClickHouse storage

**Storage Lifecycle:**
- Quick stop: EBS volumes remain (pay $4.80/month)
- Full stop: EBS volumes remain (pay $4.80/month)  
- **To eliminate cost**: Manually delete PVCs before full stop (loses all data)

## Running the ML Analyzer in EKS

### Option 1: Run as Kubernetes Job

```bash
# Copy PCAP files to EFS
kubectl cp /local/path/file.pcap l1-integrated-app-<pod-id>:/app/input_files/ -n l1-troubleshooting

# Execute analyzer
kubectl exec -it deployment/l1-integrated-app -n l1-troubleshooting -- \
  python folder_anomaly_analyzer_clickhouse.py /app/input_files
```

### Option 2: Create a CronJob for Scheduled Analysis

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: l1-analyzer-job
  namespace: l1-troubleshooting
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: analyzer
            image: <ECR_URI>:latest
            command: ["python", "folder_anomaly_analyzer_clickhouse.py", "/app/input_files"]
            volumeMounts:
            - name: input-files
              mountPath: /app/input_files
          volumes:
          - name: input-files
            persistentVolumeClaim:
              claimName: l1-input-files-pvc
          restartPolicy: OnFailure
```

## Monitoring and Troubleshooting

### View Logs
```bash
# View pod logs
kubectl logs -f deployment/l1-integrated-app -n l1-troubleshooting

# View all pods
kubectl get pods -n l1-troubleshooting

# Describe pod for detailed info
kubectl describe pod <pod-name> -n l1-troubleshooting
```

### Scale Deployment
```bash
# Manual scaling
kubectl scale deployment l1-integrated-app --replicas=5 -n l1-troubleshooting

# HPA will automatically scale based on CPU/memory
kubectl get hpa -n l1-troubleshooting
```

### Access Shell
```bash
kubectl exec -it deployment/l1-integrated-app -n l1-troubleshooting -- /bin/bash
```

## Cost Optimization

1. **Amazon Bedrock Pay-per-Use**: No model storage costs (~$3/month saved vs EFS)
   - Only pay for AI inference when analyzing anomalies
   - Nova Pro pricing: ~$0.003 per 1K input tokens, ~$0.012 per 1K output tokens
2. **Use Spot Instances** for non-critical workloads
3. **Enable Cluster Autoscaler** to scale nodes based on demand
4. **Use GP3 volumes** instead of GP2 for better price/performance
5. **Configure HPA** to scale pods dynamically (reduced resource requests: 2Gi RAM vs 4Gi)
6. **Use EFS Lifecycle Management** to move infrequently accessed files to IA storage

## Security Best Practices

1. **Use AWS Secrets Manager** with External Secrets Operator
2. **Enable Pod Security Standards**
3. **Use IAM Roles for Service Accounts (IRSA)**
4. **Enable AWS WAF** on ALB for DDoS protection
5. **Use Network Policies** to restrict pod-to-pod communication
6. **Enable EKS audit logging**
7. **Scan container images** with ECR image scanning

## Cleanup

```bash
# Delete Kubernetes resources
kubectl delete namespace l1-troubleshooting

# Delete EKS cluster
eksctl delete cluster --name l1-troubleshooting-cluster --region us-east-1

# Delete ECR repository
aws ecr delete-repository --repository-name l1-integrated --force

# Delete EFS file system
aws efs delete-file-system --file-system-id $EFS_ID
```

## Support

For issues or questions:
- Check pod logs: `kubectl logs -f deployment/l1-integrated-app -n l1-troubleshooting`
- Verify ingress: `kubectl describe ingress l1-integrated-ingress -n l1-troubleshooting`
- Review HPA status: `kubectl get hpa -n l1-troubleshooting`
