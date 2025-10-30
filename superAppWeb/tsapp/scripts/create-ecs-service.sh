#!/bin/bash

set -e

echo "=================================================="
echo "TSApp - Create ECS Service"
echo "=================================================="
echo ""

# Configuration
AWS_REGION="us-east-1"
CLUSTER_NAME="superapp-cluster"
SERVICE_NAME="tsapp-service"
TASK_DEFINITION="tsapp-task"
VPC_ID="${VPC_ID:-vpc-00f7e111e29a93774}"
SUBNET_1="${SUBNET_1:-subnet-0bf537354624ac176}"
SUBNET_2="${SUBNET_2:-subnet-0c1d10518b553764c}"

# Navigate to tsapp directory
cd "$(dirname "$0")/.."

echo "Step 1: Creating CloudWatch log group..."
aws logs create-log-group \
  --log-group-name /aws/ecs/tsapp \
  --region $AWS_REGION 2>/dev/null || echo "Log group already exists"

echo "✓ Log group ready"

echo ""
echo "Step 2: Registering ECS task definition..."
aws ecs register-task-definition \
  --cli-input-json file://ecs-task-definition.json \
  --region $AWS_REGION

echo "✓ Task definition registered"

echo ""
echo "Step 3: Creating security group for TSApp..."
SG_ID=$(aws ec2 create-security-group \
  --group-name tsapp-sg \
  --description "Security group for TSApp ECS tasks" \
  --vpc-id $VPC_ID \
  --region $AWS_REGION \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters Name=group-name,Values=tsapp-sg Name=vpc-id,Values=$VPC_ID \
    --query 'SecurityGroups[0].GroupId' \
    --region $AWS_REGION \
    --output text)

echo "✓ Security group ready: $SG_ID"

echo ""
echo "Step 4: Creating ECS service..."
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_DEFINITION \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --region $AWS_REGION

echo "✓ ECS service created"

echo ""
echo "=================================================="
echo "✓ SUCCESS! TSApp service running on ECS"
echo "=================================================="
echo ""
echo "Service details:"
echo "  Cluster: $CLUSTER_NAME"
echo "  Service: $SERVICE_NAME"
echo "  Task Definition: $TASK_DEFINITION"
echo ""
echo "View logs:"
echo "  aws logs tail /aws/ecs/tsapp --follow --region $AWS_REGION"
echo ""
echo "Check service status:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
