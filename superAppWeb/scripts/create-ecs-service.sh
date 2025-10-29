#!/bin/bash

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="superapp-cluster"
SERVICE_NAME="superapp-web-service"
TASK_FAMILY="superapp-web-task"

# YOU MUST UPDATE THESE WITH YOUR VPC DETAILS
VPC_ID="${VPC_ID:-vpc-xxxxxxxx}"
SUBNET_1="${SUBNET_1:-subnet-xxxxxxxx}"
SUBNET_2="${SUBNET_2:-subnet-yyyyyyyy}"

echo "=================================================="
echo "Creating ECS Service with Application Load Balancer"
echo "=================================================="
echo "Cluster: ${CLUSTER_NAME}"
echo "Service: ${SERVICE_NAME}"
echo "Task: ${TASK_FAMILY}"
echo "VPC: ${VPC_ID}"
echo "Subnets: ${SUBNET_1}, ${SUBNET_2}"
echo "=================================================="

# Validate VPC configuration
if [[ "${VPC_ID}" == "vpc-xxxxxxxx" ]] || [[ "${SUBNET_1}" == "subnet-xxxxxxxx" ]]; then
    echo ""
    echo "ERROR: You must set VPC_ID, SUBNET_1, and SUBNET_2 environment variables"
    echo ""
    echo "Example:"
    echo "  export VPC_ID=vpc-0123456789abcdef"
    echo "  export SUBNET_1=subnet-0123456789abcdef"
    echo "  export SUBNET_2=subnet-abcdef0123456789"
    echo "  ./scripts/create-ecs-service.sh"
    echo ""
    exit 1
fi

# Step 1: Create Security Group for ALB
echo ""
echo "Step 1: Creating ALB Security Group..."
ALB_SG_ID=$(aws ec2 create-security-group \
    --region ${AWS_REGION} \
    --group-name superapp-alb-sg \
    --description "Security group for SuperApp Application Load Balancer" \
    --vpc-id ${VPC_ID} \
    --query 'GroupId' \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --region ${AWS_REGION} \
        --filters "Name=group-name,Values=superapp-alb-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

# Allow HTTP traffic from anywhere
aws ec2 authorize-security-group-ingress \
    --region ${AWS_REGION} \
    --group-id ${ALB_SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 2>/dev/null || echo "HTTP rule already exists"

echo "✓ ALB Security Group: ${ALB_SG_ID}"

# Step 2: Create Security Group for ECS Tasks
echo ""
echo "Step 2: Creating ECS Task Security Group..."
TASK_SG_ID=$(aws ec2 create-security-group \
    --region ${AWS_REGION} \
    --group-name superapp-ecs-tasks-sg \
    --description "Security group for SuperApp ECS tasks" \
    --vpc-id ${VPC_ID} \
    --query 'GroupId' \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --region ${AWS_REGION} \
        --filters "Name=group-name,Values=superapp-ecs-tasks-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

# Allow traffic from ALB only
aws ec2 authorize-security-group-ingress \
    --region ${AWS_REGION} \
    --group-id ${TASK_SG_ID} \
    --protocol tcp \
    --port 5000 \
    --source-group ${ALB_SG_ID} 2>/dev/null || echo "Task ingress rule already exists"

echo "✓ Task Security Group: ${TASK_SG_ID}"

# Step 3: Create Application Load Balancer
echo ""
echo "Step 3: Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
    --region ${AWS_REGION} \
    --name superapp-alb \
    --subnets ${SUBNET_1} ${SUBNET_2} \
    --security-groups ${ALB_SG_ID} \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || \
    aws elbv2 describe-load-balancers \
        --region ${AWS_REGION} \
        --names superapp-alb \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)

echo "✓ ALB Created: ${ALB_ARN}"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region ${AWS_REGION} \
    --load-balancer-arns ${ALB_ARN} \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Step 4: Create Target Group
echo ""
echo "Step 4: Creating Target Group..."
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --region ${AWS_REGION} \
    --name superapp-tg \
    --protocol HTTP \
    --port 5000 \
    --vpc-id ${VPC_ID} \
    --target-type ip \
    --health-check-enabled \
    --health-check-path /api/health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || \
    aws elbv2 describe-target-groups \
        --region ${AWS_REGION} \
        --names superapp-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)

echo "✓ Target Group: ${TARGET_GROUP_ARN}"

# Step 5: Create Listener
echo ""
echo "Step 5: Creating ALB Listener..."
aws elbv2 create-listener \
    --region ${AWS_REGION} \
    --load-balancer-arn ${ALB_ARN} \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN} 2>/dev/null || \
    echo "Listener already exists"

echo "✓ Listener created"

# Step 6: Register Task Definition
echo ""
echo "Step 6: Registering Task Definition..."
aws ecs register-task-definition \
    --region ${AWS_REGION} \
    --cli-input-json file://ecs-task-definition.json

echo "✓ Task definition registered"

# Step 7: Create ECS Service
echo ""
echo "Step 7: Creating ECS Service..."
aws ecs create-service \
    --region ${AWS_REGION} \
    --cluster ${CLUSTER_NAME} \
    --service-name ${SERVICE_NAME} \
    --task-definition ${TASK_FAMILY} \
    --desired-count 1 \
    --launch-type FARGATE \
    --platform-version LATEST \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_1},${SUBNET_2}],securityGroups=[${TASK_SG_ID}],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=${TARGET_GROUP_ARN},containerName=superapp-web,containerPort=5000" \
    --health-check-grace-period-seconds 60

echo "✓ ECS service created"

echo ""
echo "=================================================="
echo "✓ Deployment Complete!"
echo "=================================================="
echo ""
echo "Your application will be accessible at:"
echo "  http://${ALB_DNS}"
echo ""
echo "It may take 2-3 minutes for the service to become healthy."
echo ""
echo "Monitor deployment:"
echo "  aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}"
echo ""
echo "View logs:"
echo "  aws logs tail /aws/ecs/superapp-web --follow"
echo "=================================================="
