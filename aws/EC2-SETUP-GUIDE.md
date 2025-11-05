# Quick Setup Guide for EC2 Console

This guide assumes you're running commands from an EC2 instance with appropriate IAM permissions.

**Get your AWS Account ID:**
```bash
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Your AWS Account ID: $AWS_ACCOUNT"
```

## Prerequisites on EC2

Ensure your EC2 instance has:
- AWS CLI installed and configured
- kubectl installed
- eksctl installed
- Helm installed
- IAM role with permissions to create EKS clusters, IAM policies, and manage Bedrock

## Step-by-Step Deployment

### 1. Clone Repository to EC2
```bash
# SSH into your EC2 instance
# Clone your project (or upload files via scp/S3)
cd ~
# Assuming files are already on EC2
cd /path/to/l1-troubleshooting-system
```

### 2. Enable Amazon Bedrock Model Access

**Via AWS Console** (open in browser):
1. Go to AWS Console → Amazon Bedrock → Model access
2. Click "Manage model access"
3. Enable **"Amazon Nova Pro"** model
4. Submit request (usually approved instantly)

### 3. Create EKS Cluster

**Option A: Use automated setup script (RECOMMENDED)**

```bash
cd aws/scripts
./setup-eks-cluster.sh l1-troubleshooting-cluster us-east-1
```

This script will:
- Create EKS cluster with nodes
- Install AWS Load Balancer Controller
- Install EBS CSI driver
- Install EFS CSI driver

Takes ~20-25 minutes. **Skip to Step 6 after this completes.**

**Option B: Manual creation**

```bash
eksctl create cluster \
  --name l1-troubleshooting-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```

This will take 15-20 minutes. Then continue with Steps 4-5.

### 4. Install Required Add-ons

**AWS Load Balancer Controller:**
```bash
# Download IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# Create service account
eksctl create iamserviceaccount \
  --cluster=l1-troubleshooting-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=l1-troubleshooting-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

**EFS CSI Driver:**
```bash
# Download EFS IAM policy
curl -o efs-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json

# Create IAM policy
aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
    --policy-document file://efs-iam-policy.json

# Create service account
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
# Get VPC ID from EKS cluster
VPC_ID=$(aws eks describe-cluster --name l1-troubleshooting-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "VPC ID: $VPC_ID"

# Create EFS file system
EFS_ID=$(aws efs create-file-system \
    --region us-east-1 \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --encrypted \
    --tags Key=Name,Value=l1-troubleshooting-efs \
    --query 'FileSystemId' --output text)

echo "EFS File System ID: $EFS_ID"
echo "Save this ID - you'll need it for configuration!"

# Get security group for EKS nodes
SG_ID=$(aws eks describe-cluster --name l1-troubleshooting-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Get subnet IDs
SUBNET_IDS=$(aws eks describe-cluster --name l1-troubleshooting-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.subnetIds" --output text)

# Create mount targets (one per subnet)
for SUBNET in $SUBNET_IDS; do
    echo "Creating mount target in subnet: $SUBNET"
    aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $SUBNET \
        --security-groups $SG_ID \
        --region us-east-1 || true
done

echo "EFS setup complete! File System ID: $EFS_ID"
```

### 6. Build and Push Docker Image to ECR

```bash
cd aws/scripts
chmod +x build-and-push.sh

# Build and push (this will take 5-10 minutes)
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
./build-and-push.sh $AWS_ACCOUNT us-east-1 latest
```

### 7. Update Configuration Files

Navigate to the `aws/kubernetes/` directory and update these files:

**Update `storageclass-efs.yaml`:**
```bash
# Replace fs-xxxxxxxxx with your actual EFS ID from step 5
sed -i "s/fs-xxxxxxxxx/$EFS_ID/g" ../kubernetes/storageclass-efs.yaml
```

**Update `deployment.yaml`:**
```bash
# Verify ECR image reference uses your account ID
cat ../kubernetes/deployment.yaml | grep "image:"
# Should show: ${AWS_ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/l1-integrated:latest
```

**Update `ingress.yaml`:**
- If you have an ACM certificate, add the ARN
- Add your domain name (or use ALB DNS)

**Update `secrets.yaml`:**
```bash
# Create secrets (replace passwords with your own)
kubectl create secret generic l1-app-secrets \
  --from-literal=CLICKHOUSE_PASSWORD='YourStrongPassword123!' \
  --from-literal=PGPASSWORD='YourPostgresPassword456!' \
  -n l1-troubleshooting \
  --dry-run=client -o yaml > temp-secrets.yaml

# Apply the secrets
kubectl apply -f temp-secrets.yaml
rm temp-secrets.yaml
```

### 8. Configure Amazon Bedrock Access (CRITICAL STEP)

```bash
cd ~/l1-troubleshooting-system/aws/kubernetes

# Create IAM policy for Bedrock
aws iam create-policy \
  --policy-name L1BedrockAccessPolicy \
  --policy-document file://bedrock-policy.json

# Create IAM service account with Bedrock permissions
# This MUST be done BEFORE running deploy.sh
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --name l1-bedrock-sa \
  --namespace l1-troubleshooting \
  --cluster l1-troubleshooting-cluster \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/L1BedrockAccessPolicy \
  --approve \
  --override-existing-serviceaccounts

# Verify service account was created
kubectl get sa l1-bedrock-sa -n l1-troubleshooting -o yaml | grep eks.amazonaws.com/role-arn
```

You should see: `eks.amazonaws.com/role-arn: arn:aws:iam::<YOUR_ACCOUNT_ID>:role/...`

### 9. Deploy Application

```bash
cd ~/l1-troubleshooting-system/aws/scripts
chmod +x deploy.sh

# Deploy all Kubernetes resources
./deploy.sh l1-troubleshooting-cluster us-east-1
```

Wait for deployment to complete (2-3 minutes).

### 10. Get Application URL

```bash
# Wait for ALB to be provisioned
kubectl get ingress -n l1-troubleshooting -w
# Press Ctrl+C after you see the ADDRESS column populated

# Get the ALB URL
ALB_URL=$(kubectl get ingress l1-integrated-ingress -n l1-troubleshooting -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://$ALB_URL"
```

Access your L1 Troubleshooting UI at: `http://<ALB_URL>`

## Verification

### Check Pod Status
```bash
kubectl get pods -n l1-troubleshooting
# All pods should show "Running"
```

### Check Bedrock Access
```bash
# Get pod name
POD=$(kubectl get pod -n l1-troubleshooting -l app=l1-integrated -o jsonpath='{.items[0].metadata.name}')

# Check AI inference server logs
kubectl logs -n l1-troubleshooting $POD | grep -i bedrock

# You should see: "Bedrock client initialized successfully"
```

### Test AI Recommendations
1. Open the web UI: `http://<ALB_URL>`
2. Upload a PCAP/DLF file for analysis
3. Click "Recommend" on any detected anomaly
4. You should see streaming AI recommendations from Bedrock Nova Pro

## Troubleshooting from EC2

### Pods not starting
```bash
kubectl describe pod -n l1-troubleshooting <pod-name>
kubectl logs -n l1-troubleshooting <pod-name>
```

### Bedrock access denied
```bash
# Check if service account has correct IAM role
kubectl get sa l1-bedrock-sa -n l1-troubleshooting -o yaml

# Verify the role exists
aws iam get-role --role-name eksctl-l1-troubleshooting-cluster-addon-iamserviceaccou-Role1-XXXXX
```

### EFS mount issues
```bash
kubectl get pvc -n l1-troubleshooting
kubectl describe pvc l1-input-files-pvc -n l1-troubleshooting
```

### View all logs
```bash
# Application logs
kubectl logs -f deployment/l1-integrated-app -n l1-troubleshooting

# Ingress controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

## Cost Estimate for 4-Hour Usage

**Per 4-Hour Session:**
- EKS Control Plane: $0.40 (4 hours × $0.10/hour)
- 2× t3.large nodes: $0.67 (4 hours × 2 nodes × $0.0832/hour)
- Load Balancer: $0.09 (4 hours × $0.0225/hour)
- Bedrock Nova Pro: ~$0.50-2.00 (pay-per-use, depends on analysis volume)
- **Total per session: ~$1.66-3.16**

**Monthly Cost (using 1× per week):**
- 4 sessions/month × $2.50 = **~$10/month**
- EFS storage (persistent): ~$5/month
- ECR image storage: ~$1/month
- **Total: ~$16/month** for weekly 4-hour sessions

**⚠️ CRITICAL - Cost Control:**
After each 4-hour session, you MUST run the stop script to avoid charges:
```bash
cd aws/scripts
./stop-all-services.sh full  # Complete shutdown (near-zero idle cost)
```

If you forget to stop:
- Idle cost: ~$87/month (cluster running, no workload)
- Active 24/7: ~$250/month

## Recommended Workflow for 4-Hour Sessions

**Before Starting Work:**
```bash
# 1. Start services
cd aws/scripts
./start-all-services.sh quick

# 2. Wait ~5 minutes, then get URL
kubectl get ingress -n l1-troubleshooting

# 3. Access application
# Open http://<ALB-URL> in browser
```

**During Your Session (4 hours max):**
- Upload PCAP/DLF files for analysis
- Use AI recommendations (Bedrock Nova Pro)
- Review dashboard and anomaly reports
- Export results if needed

**After Finishing Work (CRITICAL!):**
```bash
# Stop everything to prevent charges
cd aws/scripts
./stop-all-services.sh quick

# Or for maximum savings (if not using for weeks):
./stop-all-services.sh full
```

**Weekly Cost Control Checklist:**
- [ ] Start services only when needed
- [ ] Upload and analyze your network files
- [ ] Export/save any important results
- [ ] Stop services immediately after session
- [ ] Run `./check-costs.sh` weekly to verify nothing is running

## Next Steps

1. Set up CloudWatch billing alerts (prevent surprise charges)
2. Configure automated backups for EFS (optional)
3. Create CloudWatch alarm for "cluster still running" after 5 hours

## 🛑 STOPPING Services After 4-Hour Session (IMPORTANT!)

**Quick Stop (Recommended for regular use):**
```bash
cd aws/scripts
./stop-all-services.sh quick
```
- Stops all pods and scales nodes to 0
- Idle cost: ~$2.40/day (EKS control plane only)
- Restart time: ~5 minutes
- Use when you'll use the system again soon

**Full Stop (Best for long breaks):**
```bash
cd aws/scripts
./stop-all-services.sh full
```
- Deletes entire cluster
- Idle cost: ~$0.60/day (only EFS/ECR storage)
- Restart time: ~25 minutes
- Use when you won't use the system for weeks

**Check Current Costs:**
```bash
cd aws/scripts
./check-costs.sh
```
Shows what's running and estimated costs in real-time.

## 🚀 STARTING Services for Next Session

**Quick Start (after quick stop):**
```bash
cd aws/scripts
./start-all-services.sh quick
```
Ready in ~5 minutes

**Full Start (after full stop):**
```bash
cd aws/scripts
./start-all-services.sh full
```
Ready in ~25 minutes (recreates entire cluster)

## Quick Commands Reference

```bash
# Check what's running and costs
./check-costs.sh

# Stop after session
./stop-all-services.sh quick    # Fast restart later
./stop-all-services.sh full     # Maximum savings

# Start for next session
./start-all-services.sh quick   # If you did quick stop
./start-all-services.sh full    # If you did full stop

# During active session
kubectl get pods -n l1-troubleshooting              # Check pod status
kubectl logs -f deployment/l1-integrated-app -n l1-troubleshooting  # View logs
kubectl get ingress -n l1-troubleshooting           # Get URL

# Access pod shell
kubectl exec -it deployment/l1-integrated-app -n l1-troubleshooting -- /bin/bash
```

---

**Account ID**: Get via `aws sts get-caller-identity --query Account --output text`  
**Region**: us-east-1  
**Cluster**: l1-troubleshooting-cluster
