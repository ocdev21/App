# AWS Infrastructure for L1 Troubleshooting System

This directory contains Infrastructure as Code (IaC) for provisioning AWS resources needed for the L1 Troubleshooting System.

## Option 1: Terraform (Recommended for Production)

### Prerequisites
```bash
# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Update kubectl config
```bash
aws eks update-kubeconfig --name l1-troubleshooting-cluster --region us-east-1
```

## Option 2: eksctl (Quick Start)

```bash
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Create cluster with config file
eksctl create cluster -f eksctl-config.yaml
```

### eksctl-config.yaml Example

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: l1-troubleshooting-cluster
  region: us-east-1
  version: "1.28"

vpc:
  cidr: 10.0.0.0/16

managedNodeGroups:
  - name: general-workers
    instanceType: t3.xlarge
    minSize: 2
    maxSize: 10
    desiredCapacity: 3
    volumeSize: 50
    labels:
      role: general
    tags:
      nodegroup-role: general

iam:
  withOIDC: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
  - name: aws-efs-csi-driver
```

## Resources Created

1. **VPC**: Multi-AZ VPC with public and private subnets
2. **EKS Cluster**: Managed Kubernetes cluster
3. **Node Groups**: Auto-scaling worker nodes
4. **EFS**: Shared file system for models and data
5. **ECR**: Container registry for Docker images
6. **IAM Roles**: Service accounts and permissions
7. **Security Groups**: Network access controls

## Estimated Monthly Costs

- EKS Cluster: ~$75/month
- EC2 Nodes (3x t3.xlarge): ~$450/month
- EFS Storage (50GB): ~$15/month
- EBS Volumes (150GB GP3): ~$15/month
- Data Transfer: Variable
- **Total**: ~$555/month (excluding data transfer)

## Cleanup

### Terraform
```bash
terraform destroy
```

### eksctl
```bash
eksctl delete cluster --name l1-troubleshooting-cluster
```
