#!/bin/bash

set -e

# Configuration
AWS_ACCOUNT_ID="012351853258"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="superapp-cluster"
SERVICE_NAME="superapp-web-service"
TASK_FAMILY="superapp-web-task"

echo "=================================================="
echo "Setting Up ECS Infrastructure for SuperApp"
echo "=================================================="

# Step 1: Create CloudWatch Log Group
echo ""
echo "Step 1: Creating CloudWatch Log Group..."
if ! aws logs describe-log-groups \
    --region ${AWS_REGION} \
    --log-group-name-prefix "/aws/ecs/superapp-web" 2>/dev/null | grep -q "/aws/ecs/superapp-web"; then
    
    aws logs create-log-group \
        --region ${AWS_REGION} \
        --log-group-name "/aws/ecs/superapp-web"
    
    aws logs put-retention-policy \
        --region ${AWS_REGION} \
        --log-group-name "/aws/ecs/superapp-web" \
        --retention-in-days 7
    
    echo "✓ Log group created"
else
    echo "✓ Log group already exists"
fi

# Step 2: Create ECS Execution Role (if not exists)
echo ""
echo "Step 2: Creating ECS Execution Role..."
if ! aws iam get-role --role-name superapp-ecs-execution 2>/dev/null; then
    
    # Create trust policy
    cat > /tmp/ecs-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name superapp-ecs-execution \
        --assume-role-policy-document file:///tmp/ecs-execution-trust-policy.json \
        --description "ECS task execution role for SuperApp"
    
    # Attach AWS managed policy for ECS task execution
    aws iam attach-role-policy \
        --role-name superapp-ecs-execution \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Attach ECR read policy
    cat > /tmp/ecr-read-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:superapp/*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name superapp-ecs-execution \
        --policy-name ECRAccessPolicy \
        --policy-document file:///tmp/ecr-read-policy.json
    
    echo "✓ ECS execution role created"
    
    # Wait for role to propagate
    echo "Waiting for role to propagate..."
    sleep 10
else
    echo "✓ ECS execution role already exists"
fi

# Step 3: Create ECS Cluster
echo ""
echo "Step 3: Creating ECS Cluster..."
if ! aws ecs describe-clusters \
    --region ${AWS_REGION} \
    --clusters ${CLUSTER_NAME} 2>/dev/null | grep -q "ACTIVE"; then
    
    aws ecs create-cluster \
        --region ${AWS_REGION} \
        --cluster-name ${CLUSTER_NAME} \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy \
            capacityProvider=FARGATE,weight=1,base=1 \
            capacityProvider=FARGATE_SPOT,weight=4
    
    echo "✓ ECS cluster created"
else
    echo "✓ ECS cluster already exists"
fi

# Step 4: Create Session Secret in Secrets Manager (if not exists)
echo ""
echo "Step 4: Creating session secret..."
if ! aws secretsmanager describe-secret \
    --region ${AWS_REGION} \
    --secret-id superapp/session-secret 2>/dev/null; then
    
    # Generate random secret
    SECRET_VALUE=$(openssl rand -base64 32)
    
    aws secretsmanager create-secret \
        --region ${AWS_REGION} \
        --name superapp/session-secret \
        --description "Session secret for SuperApp web application" \
        --secret-string "${SECRET_VALUE}"
    
    echo "✓ Session secret created"
else
    echo "✓ Session secret already exists"
fi

echo ""
echo "=================================================="
echo "✓ ECS Infrastructure Setup Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Register task definition:"
echo "   aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json"
echo ""
echo "2. Create ECS service (you'll need VPC/subnet IDs):"
echo "   See: scripts/create-ecs-service.sh"
echo "=================================================="
