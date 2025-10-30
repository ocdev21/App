#!/bin/bash

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="012351853258"

echo "=================================================="
echo "Creating IAM Roles for ECS"
echo "=================================================="

# Step 1: Create ECS Execution Role
echo ""
echo "Step 1: Creating ECS Execution Role..."

EXECUTION_ROLE_EXISTS=$(aws iam get-role \
    --role-name superapp-ecs-execution \
    --query 'Role.RoleName' \
    --output text 2>/dev/null || echo "")

if [ -z "${EXECUTION_ROLE_EXISTS}" ]; then
    echo "Creating superapp-ecs-execution role..."
    
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
        --description "Execution role for SuperApp ECS tasks"
    
    # Attach AWS managed policy for ECS task execution
    aws iam attach-role-policy \
        --role-name superapp-ecs-execution \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Add Secrets Manager access
    cat > /tmp/secrets-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:superapp/*"
      ]
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name superapp-ecs-execution \
        --policy-name SecretsManagerAccess \
        --policy-document file:///tmp/secrets-policy.json
    
    echo "✓ superapp-ecs-execution role created"
else
    echo "✓ superapp-ecs-execution role already exists"
fi

# Step 2: Create ECS Task Role (for Bedrock and Timestream access)
echo ""
echo "Step 2: Creating ECS Task Role..."

TASK_ROLE_EXISTS=$(aws iam get-role \
    --role-name superapp-sagemaker-execution \
    --query 'Role.RoleName' \
    --output text 2>/dev/null || echo "")

if [ -z "${TASK_ROLE_EXISTS}" ]; then
    echo "Creating superapp-sagemaker-execution role..."
    
    # Create trust policy
    cat > /tmp/ecs-task-trust-policy.json <<EOF
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
        --role-name superapp-sagemaker-execution \
        --assume-role-policy-document file:///tmp/ecs-task-trust-policy.json \
        --description "Task role for SuperApp with Bedrock and Timestream access"
    
    # Create and attach Bedrock policy
    cat > /tmp/bedrock-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name superapp-sagemaker-execution \
        --policy-name BedrockAccess \
        --policy-document file:///tmp/bedrock-policy.json
    
    # Create and attach Timestream policy
    cat > /tmp/timestream-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:Select",
        "timestream:DescribeTable",
        "timestream:DescribeDatabase"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "timestream:CreateDatabase",
        "timestream:CreateTable",
        "timestream:WriteRecords"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name superapp-sagemaker-execution \
        --policy-name TimestreamAccess \
        --policy-document file:///tmp/timestream-policy.json
    
    echo "✓ superapp-sagemaker-execution role created"
else
    echo "✓ superapp-sagemaker-execution role already exists"
fi

# Wait for IAM to propagate
echo ""
echo "Waiting 10 seconds for IAM roles to propagate..."
sleep 10

echo ""
echo "=================================================="
echo "✓ IAM Roles Created Successfully"
echo "=================================================="
echo ""
echo "Roles created:"
echo "  - superapp-ecs-execution (for ECS task execution)"
echo "  - superapp-sagemaker-execution (for Bedrock + Timestream access)"
echo ""
echo "You can now register the task definition and create the service."
echo "=================================================="

# Cleanup temp files
rm -f /tmp/ecs-execution-trust-policy.json
rm -f /tmp/ecs-task-trust-policy.json
rm -f /tmp/secrets-policy.json
rm -f /tmp/bedrock-policy.json
rm -f /tmp/timestream-policy.json
