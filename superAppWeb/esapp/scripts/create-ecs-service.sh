#!/bin/bash

set -e

echo "=================================================="
echo "ESApp - Create ECS Service"
echo "=================================================="
echo ""

# Configuration
AWS_REGION="us-east-1"
CLUSTER_NAME="superapp-cluster"
SERVICE_NAME="esapp-service"
TASK_DEFINITION="esapp-task"
VPC_ID="${VPC_ID:-vpc-00f7e111e29a93774}"
SUBNET_1="${SUBNET_1:-subnet-0bf537354624ac176}"
SUBNET_2="${SUBNET_2:-subnet-0c1d10518b553764c}"

# Navigate to esapp directory
cd "$(dirname "$0")/.."

echo "Step 1: Creating CloudWatch log group..."
aws logs create-log-group \
  --log-group-name /aws/ecs/esapp \
  --region $AWS_REGION 2>/dev/null || echo "Log group already exists"

echo "✓ Log group ready"

echo ""
echo "Step 2: Registering ECS task definition..."
aws ecs register-task-definition \
  --cli-input-json file://ecs-task-definition.json \
  --region $AWS_REGION

echo "✓ Task definition registered"

echo ""
echo "Step 3: Creating security group for ESApp..."
SG_ID=$(aws ec2 create-security-group \
  --group-name esapp-sg \
  --description "Security group for ESApp ECS tasks" \
  --vpc-id $VPC_ID \
  --region $AWS_REGION \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters Name=group-name,Values=esapp-sg Name=vpc-id,Values=$VPC_ID \
    --query 'SecurityGroups[0].GroupId' \
    --region $AWS_REGION \
    --output text)

echo "✓ Security group ready: $SG_ID"

echo ""
echo "Step 4: Checking if ECS service exists..."
SERVICE_STATUS=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].status' \
  --output text 2>/dev/null)

if [ "$SERVICE_STATUS" == "ACTIVE" ]; then
  echo "Service is ACTIVE, updating with new task definition..."
  aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $TASK_DEFINITION \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null
  echo "✓ ECS service updated"
elif [ "$SERVICE_STATUS" == "DRAINING" ] || [ "$SERVICE_STATUS" == "INACTIVE" ]; then
  echo "Service exists but is $SERVICE_STATUS. Deleting and recreating..."
  aws ecs delete-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force \
    --region $AWS_REGION > /dev/null
  echo "Waiting for service deletion..."
  sleep 10
  echo "Creating new ECS service..."
  aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition $TASK_DEFINITION \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region $AWS_REGION > /dev/null
  echo "✓ ECS service created"
elif [ "$SERVICE_STATUS" == "None" ] || [ -z "$SERVICE_STATUS" ]; then
  echo "Creating new ECS service..."
  aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition $TASK_DEFINITION \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region $AWS_REGION > /dev/null
  echo "✓ ECS service created"
else
  echo "⚠️  Service in unexpected state: $SERVICE_STATUS"
  echo "Attempting to update..."
  aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $TASK_DEFINITION \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null || {
      echo "Update failed. Trying to delete and recreate..."
      aws ecs delete-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force \
        --region $AWS_REGION > /dev/null
      sleep 10
      aws ecs create-service \
        --cluster $CLUSTER_NAME \
        --service-name $SERVICE_NAME \
        --task-definition $TASK_DEFINITION \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --region $AWS_REGION > /dev/null
    }
  echo "✓ ECS service ready"
fi

echo ""
echo "=================================================="
echo "✓ SUCCESS! ESApp service running on ECS"
echo "=================================================="
echo ""
echo "Service details:"
echo "  Cluster: $CLUSTER_NAME"
echo "  Service: $SERVICE_NAME"
echo "  Task Definition: $TASK_DEFINITION"
echo ""
echo "View logs:"
echo "  aws logs tail /aws/ecs/esapp --follow --region $AWS_REGION"
echo ""
echo "Check service status:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
