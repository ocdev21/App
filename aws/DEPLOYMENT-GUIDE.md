# Quick Deployment Guide - AWS EKS

## TL;DR - Fast Track Deployment

### 1. Prerequisites (One-time setup)
```bash
# Install required tools
brew install awscli kubectl helm eksctl terraform  # macOS
# or use package manager on Linux

# Configure AWS
aws configure
```

### 2. Build & Push Image to ECR
```bash
cd aws/scripts
./build-and-push.sh 123456789012 us-east-1 latest
```

### 3. Deploy Infrastructure (Choose One)

**Option A: Using eksctl (Fastest)**
```bash
eksctl create cluster \
  --name l1-cluster \
  --region us-east-1 \
  --nodegroup-name workers \
  --node-type t3.xlarge \
  --nodes 3
```

**Option B: Using Terraform (Production)**
```bash
cd aws/infrastructure
terraform init
terraform apply
```

### 4. Install Required Add-ons
```bash
# AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=l1-cluster

# EFS CSI Driver
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  -n kube-system
```

### 5. Update Configuration Files

**Update these files with your values:**
- `kubernetes/storageclass-efs.yaml` - Add your EFS ID
- `kubernetes/deployment.yaml` - Add your ECR image URI
- `kubernetes/ingress.yaml` - Add your ACM certificate ARN and domain
- `kubernetes/secrets.yaml` - Add your passwords

### 6. Configure Amazon Bedrock Access

**Step 6a: Enable Bedrock Model Access**
1. Go to AWS Console → Amazon Bedrock → Model access
2. Click "Manage model access"
3. Enable "Amazon Nova Pro"
4. Submit request (usually approved instantly)

**Step 6b: Create IAM Policy**
```bash
# From your EC2 console, navigate to the aws directory
cd aws/kubernetes
aws iam create-policy \
  --policy-name L1BedrockAccessPolicy \
  --policy-document file://bedrock-policy.json
```

**Step 6c: Create Service Account with IAM Role (IRSA)**
```bash
# IMPORTANT: Run this BEFORE deploy.sh
# Account ID: 012351853258
eksctl create iamserviceaccount \
  --name l1-bedrock-sa \
  --namespace l1-troubleshooting \
  --cluster l1-cluster \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::012351853258:policy/L1BedrockAccessPolicy \
  --approve \
  --override-existing-serviceaccounts
```

### 7. Deploy Application
```bash
cd aws/scripts
./deploy.sh l1-cluster us-east-1
```

### 8. Get Your Application URL
```bash
kubectl get ingress -n l1-troubleshooting
# Wait 2-3 minutes for ALB provisioning
```

## Accessing the UI

Your L1 Troubleshooting web interface will be available at:
- **ALB URL**: `https://<alb-dns-name>.elb.amazonaws.com`
- **Custom Domain**: `https://l1-troubleshooting.yourdomain.com` (after DNS setup)

## Common Tasks

### Upload Network Files for Analysis
```bash
# Get pod name
POD=$(kubectl get pod -n l1-troubleshooting -l app=l1-integrated -o jsonpath='{.items[0].metadata.name}')

# Upload PCAP file
kubectl cp /local/path/capture.pcap l1-troubleshooting/$POD:/app/input_files/

# Run analyzer
kubectl exec -n l1-troubleshooting $POD -- \
  python folder_anomaly_analyzer_clickhouse.py /app/input_files
```

### View Logs
```bash
kubectl logs -f -n l1-troubleshooting deployment/l1-integrated-app
```

### Scale Application
```bash
# Manual scaling
kubectl scale deployment l1-integrated-app -n l1-troubleshooting --replicas=5

# Auto-scaling is configured via HPA (2-10 pods)
```

## Folder Structure

```
aws/
├── Dockerfile                      # AWS-optimized container image
├── README.md                       # Comprehensive deployment guide
├── DEPLOYMENT-GUIDE.md            # This quick start guide
│
├── kubernetes/                     # Kubernetes manifests
│   ├── namespace.yaml             # l1-troubleshooting namespace
│   ├── configmap.yaml             # Application configuration
│   ├── secrets.yaml               # Sensitive credentials
│   ├── pvc.yaml                   # EFS/EBS storage claims
│   ├── storageclass-efs.yaml      # EFS StorageClass
│   ├── deployment.yaml            # Main application deployment
│   ├── service.yaml               # Kubernetes service
│   ├── ingress.yaml               # ALB ingress configuration
│   └── hpa.yaml                   # Auto-scaling configuration
│
├── scripts/                        # Deployment automation
│   ├── build-and-push.sh          # Build & push to ECR
│   └── deploy.sh                  # Deploy to EKS
│
└── infrastructure/                 # IaC templates
    ├── terraform-example.tf       # Terraform configuration
    └── README.md                  # Infrastructure guide
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n l1-troubleshooting
kubectl logs -n l1-troubleshooting <pod-name>
```

### ALB not created
```bash
# Check ingress events
kubectl describe ingress l1-integrated-ingress -n l1-troubleshooting

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### EFS mount issues
```bash
# Verify EFS CSI driver
kubectl get pods -n kube-system | grep efs

# Check PVC status
kubectl get pvc -n l1-troubleshooting
```

## Cost Management

- **Bedrock Pay-per-Use**: No model storage costs (~$3/month saved)
  - Nova Pro: ~$0.003 per 1K input tokens, ~$0.012 per 1K output tokens
- **Start small**: Begin with 2 t3.large nodes (~$150/month, reduced from t3.xlarge)
- **Use Spot instances**: Save up to 70% on compute costs
- **Enable autoscaling**: Scale down during off-hours
- **Monitor usage**: Use AWS Cost Explorer to track spending

## Next Steps

1. Configure custom domain in Route53
2. Enable AWS WAF for security
3. Setup CloudWatch dashboards for monitoring
4. Configure backup policies for EFS
5. Implement CI/CD pipeline with GitHub Actions
