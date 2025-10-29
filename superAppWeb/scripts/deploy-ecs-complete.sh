#!/bin/bash

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="012351853258"
CLUSTER_NAME="superapp-cluster"
SERVICE_NAME="superapp-service"
TASK_FAMILY="superapp-task"

# VPC Configuration
VPC_ID="${VPC_ID:-vpc-00f7e111e29a93774}"
SUBNET_1="${SUBNET_1:-subnet-0bf537354624ac176}"
SUBNET_2="${SUBNET_2:-subnet-0c1d10518b553764c}"

echo "=================================================="
echo "Complete ECS Deployment (No Load Balancer)"
echo "=================================================="
echo "Cluster: ${CLUSTER_NAME}"
echo "Service: ${SERVICE_NAME}"
echo "Task: ${TASK_FAMILY}"
echo "VPC: ${VPC_ID}"
echo "Subnets: ${SUBNET_1}, ${SUBNET_2}"
echo "=================================================="

# Step 0: Create session secret if it doesn't exist
echo ""
echo "Step 0: Ensuring session secret exists..."
SECRET_EXISTS=$(aws secretsmanager describe-secret \
    --secret-id superapp/session-secret \
    --region ${AWS_REGION} \
    --query 'ARN' \
    --output text 2>/dev/null || echo "")

if [ -z "${SECRET_EXISTS}" ]; then
    echo "Creating session secret..."
    SECRET_VALUE=$(openssl rand -base64 32)
    aws secretsmanager create-secret \
        --name superapp/session-secret \
        --description "Session secret for SuperApp" \
        --secret-string "${SECRET_VALUE}" \
        --region ${AWS_REGION}
    echo "✓ Session secret created"
else
    echo "✓ Session secret already exists"
fi

# Step 1: Create Security Group for ECS Tasks
echo ""
echo "Step 1: Creating ECS Task Security Group..."
TASK_SG_ID=$(aws ec2 describe-security-groups \
    --region ${AWS_REGION} \
    --filters "Name=group-name,Values=superapp-ecs-tasks-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [ "${TASK_SG_ID}" == "None" ] || [ -z "${TASK_SG_ID}" ]; then
    echo "Creating new security group..."
    TASK_SG_ID=$(aws ec2 create-security-group \
        --region ${AWS_REGION} \
        --group-name superapp-ecs-tasks-sg \
        --description "Security group for SuperApp ECS tasks" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' \
        --output text)
    
    sleep 3
    
    # Allow HTTP traffic from anywhere (since no ALB)
    aws ec2 authorize-security-group-ingress \
        --region ${AWS_REGION} \
        --group-id ${TASK_SG_ID} \
        --protocol tcp \
        --port 5000 \
        --cidr 0.0.0.0/0
else
    echo "Security group already exists"
    # Try to add ingress rule (ignore if exists)
    aws ec2 authorize-security-group-ingress \
        --region ${AWS_REGION} \
        --group-id ${TASK_SG_ID} \
        --protocol tcp \
        --port 5000 \
        --cidr 0.0.0.0/0 2>/dev/null || echo "Ingress rule already exists"
fi

echo "✓ Task Security Group: ${TASK_SG_ID}"

# Step 2: Create CloudWatch Log Group
echo ""
echo "Step 2: Creating CloudWatch Log Group..."
aws logs create-log-group \
    --log-group-name /aws/ecs/superapp-web \
    --region ${AWS_REGION} 2>/dev/null || echo "Log group already exists"

aws logs put-retention-policy \
    --log-group-name /aws/ecs/superapp-web \
    --retention-in-days 7 \
    --region ${AWS_REGION} 2>/dev/null || echo "Retention policy already set"

echo "✓ CloudWatch Log Group ready"

# Step 3: Register Task Definition
echo ""
echo "Step 3: Registering Task Definition..."

# Create task definition JSON
cat > /tmp/superapp-task-definition.json <<EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/superapp-ecs-execution",
  "taskRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/superapp-sagemaker-execution",
  "containerDefinitions": [
    {
      "name": "superapp-web",
      "image": "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/superapp:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 5000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "PORT",
          "value": "5000"
        },
        {
          "name": "AWS_REGION",
          "value": "${AWS_REGION}"
        },
        {
          "name": "TIMESTREAM_DATABASE_NAME",
          "value": "SuperAppDB"
        }
      ],
      "secrets": [
        {
          "name": "SESSION_SECRET",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:superapp/session-secret"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/aws/ecs/superapp-web",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "node -e \"require('http').get('http://localhost:5000/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})\""
        ],
        "interval": 30,
        "timeout": 10,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Register the task definition
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --region ${AWS_REGION} \
    --cli-input-json file:///tmp/superapp-task-definition.json \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "✓ Task definition registered: ${TASK_DEF_ARN}"

# Step 4: Create/Update ECS Service
echo ""
echo "Step 4: Creating ECS Service..."

# Check if service exists
EXISTING_SERVICE=$(aws ecs describe-services \
    --region ${AWS_REGION} \
    --cluster ${CLUSTER_NAME} \
    --services ${SERVICE_NAME} \
    --query 'services[?status==`ACTIVE`].serviceName' \
    --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_SERVICE}" ]; then
    echo "Service already exists, updating..."
    aws ecs update-service \
        --region ${AWS_REGION} \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --task-definition ${TASK_FAMILY} \
        --desired-count 1 \
        --force-new-deployment
else
    echo "Creating new service..."
    aws ecs create-service \
        --region ${AWS_REGION} \
        --cluster ${CLUSTER_NAME} \
        --service-name ${SERVICE_NAME} \
        --task-definition ${TASK_FAMILY} \
        --desired-count 1 \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_1},${SUBNET_2}],securityGroups=[${TASK_SG_ID}],assignPublicIp=ENABLED}"
fi

echo "✓ ECS service created/updated"

# Wait for task to start
echo ""
echo "Waiting for task to start (this may take 2-3 minutes)..."
sleep 30

# Step 5: Get Public IP
echo ""
echo "Step 5: Finding public IP address..."
TASK_ARN=$(aws ecs list-tasks \
    --region ${AWS_REGION} \
    --cluster ${CLUSTER_NAME} \
    --service-name ${SERVICE_NAME} \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text)

if [ -n "${TASK_ARN}" ] && [ "${TASK_ARN}" != "None" ]; then
    # Get ENI ID
    ENI_ID=$(aws ecs describe-tasks \
        --region ${AWS_REGION} \
        --cluster ${CLUSTER_NAME} \
        --tasks ${TASK_ARN} \
        --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
        --output text)
    
    if [ -n "${ENI_ID}" ]; then
        # Get public IP
        PUBLIC_IP=$(aws ec2 describe-network-interfaces \
            --region ${AWS_REGION} \
            --network-interface-ids ${ENI_ID} \
            --query 'NetworkInterfaces[0].Association.PublicIp' \
            --output text)
        
        echo "✓ Public IP: ${PUBLIC_IP}"
    fi
fi

# Cleanup temp file
rm -f /tmp/superapp-task-definition.json

echo ""
echo "=================================================="
echo "✓ Deployment Complete!"
echo "=================================================="
echo ""
if [ -n "${PUBLIC_IP}" ] && [ "${PUBLIC_IP}" != "None" ]; then
    echo "Your application is accessible at:"
    echo "  http://${PUBLIC_IP}:5000"
    echo ""
    echo "Test it:"
    echo "  curl http://${PUBLIC_IP}:5000/api/health"
else
    echo "Task is starting. Get the public IP with:"
    echo "  aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --region ${AWS_REGION}"
    echo ""
    echo "Then wait 1-2 minutes and run this script again to get the IP"
fi
echo ""
echo "Monitor deployment:"
echo "  aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}"
echo ""
echo "View logs:"
echo "  aws logs tail /aws/ecs/superapp-web --follow --region ${AWS_REGION}"
echo "=================================================="
