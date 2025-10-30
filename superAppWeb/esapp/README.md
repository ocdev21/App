# ESApp - Energy Application

Python-based continuous background task running on AWS ECS Fargate.

## Overview

**Entry Point:** `energy_19.py`  
**Purpose:** Background processing task that runs continuously  
**Platform:** AWS ECS Fargate (serverless containers)

## Architecture

- **Runtime:** Python 3.11
- **Execution Role:** `superapp-ecs-execution` (shared)
- **Task Role:** `superapp-sagemaker-execution` (shared with Bedrock/Timestream access)
- **ECR Repository:** `esapp` (separate from superapp)
- **ECS Cluster:** `superapp-cluster` (shared)
- **Resources:** 256 CPU, 512 MB memory

## Deployment

### Prerequisites
- AWS CLI configured with credentials
- Docker installed
- VPC and subnets configured
- IAM roles `superapp-ecs-execution` and `superapp-sagemaker-execution` exist

### Step 1: Build and Push to ECR

```bash
cd esapp
chmod +x scripts/deployes-to-ecr.sh
./scripts/deployes-to-ecr.sh
```

This will:
- Create ECR repository `esapp` (if not exists)
- Build Docker image
- Push to ECR

### Step 2: Deploy to ECS

```bash
chmod +x scripts/create-ecs-service.sh
./scripts/create-ecs-service.sh
```

This will:
- Create CloudWatch log group `/aws/ecs/esapp`
- Register ECS task definition
- Create security group
- Create ECS service with 1 running task

## Monitoring

### View Logs
```bash
aws logs tail /aws/ecs/esapp --follow --region us-east-1
```

### Check Service Status
```bash
aws ecs describe-services \
  --cluster superapp-cluster \
  --services esapp-service \
  --region us-east-1
```

### List Running Tasks
```bash
aws ecs list-tasks \
  --cluster superapp-cluster \
  --service-name esapp-service \
  --region us-east-1
```

## Configuration

Edit `ecs-task-definition.json` to modify:
- CPU/Memory allocation
- Environment variables
- IAM roles

## Stopping the Service

```bash
aws ecs update-service \
  --cluster superapp-cluster \
  --service esapp-service \
  --desired-count 0 \
  --region us-east-1
```

## Deleting the Service

```bash
aws ecs delete-service \
  --cluster superapp-cluster \
  --service esapp-service \
  --force \
  --region us-east-1
```
