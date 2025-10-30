#!/bin/bash

set -e

# Configuration
AWS_ACCOUNT_ID="012351853258"
AWS_REGION="${AWS_REGION:-us-east-1}"
TASK_ROLE_NAME="superapp-sagemaker-execution"

echo "=================================================="
echo "Adding AWS Service Permissions to ECS Task Role"
echo "=================================================="
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"
echo "Task Role: ${TASK_ROLE_NAME}"
echo "=================================================="

# Step 1: Create Bedrock policy
echo ""
echo "Step 1: Creating Bedrock policy..."

BEDROCK_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": [
        "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
        "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
        "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0"
      ]
    }
  ]
}
EOF
)

# Create or update Bedrock policy
BEDROCK_POLICY_NAME="superapp-bedrock-access"
BEDROCK_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${BEDROCK_POLICY_NAME}"

if aws iam get-policy --policy-arn ${BEDROCK_POLICY_ARN} --region ${AWS_REGION} 2>/dev/null; then
    echo "Policy ${BEDROCK_POLICY_NAME} already exists, updating..."
    
    # Get current default version
    CURRENT_VERSION=$(aws iam get-policy \
        --policy-arn ${BEDROCK_POLICY_ARN} \
        --query 'Policy.DefaultVersionId' \
        --output text)
    
    # Create new version
    aws iam create-policy-version \
        --policy-arn ${BEDROCK_POLICY_ARN} \
        --policy-document "${BEDROCK_POLICY}" \
        --set-as-default
    
    # Delete old version
    aws iam delete-policy-version \
        --policy-arn ${BEDROCK_POLICY_ARN} \
        --version-id ${CURRENT_VERSION}
    
    echo "✓ Policy updated"
else
    echo "Creating new policy ${BEDROCK_POLICY_NAME}..."
    aws iam create-policy \
        --policy-name ${BEDROCK_POLICY_NAME} \
        --policy-document "${BEDROCK_POLICY}" \
        --description "Allows ECS tasks to access AWS Bedrock Claude models"
    
    echo "✓ Policy created"
fi

# Step 2: Create Timestream policy
echo ""
echo "Step 2: Creating Timestream policy..."

TIMESTREAM_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:CreateDatabase",
        "timestream:DescribeDatabase",
        "timestream:ListDatabases"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "timestream:CreateTable",
        "timestream:DescribeTable",
        "timestream:ListTables",
        "timestream:UpdateTable",
        "timestream:WriteRecords",
        "timestream:Select",
        "timestream:SelectValues",
        "timestream:CancelQuery"
      ],
      "Resource": [
        "arn:aws:timestream:${AWS_REGION}:${AWS_ACCOUNT_ID}:database/SuperAppDB",
        "arn:aws:timestream:${AWS_REGION}:${AWS_ACCOUNT_ID}:database/SuperAppDB/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "timestream:DescribeEndpoints"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

# Create or update Timestream policy
TIMESTREAM_POLICY_NAME="superapp-timestream-access"
TIMESTREAM_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${TIMESTREAM_POLICY_NAME}"

if aws iam get-policy --policy-arn ${TIMESTREAM_POLICY_ARN} --region ${AWS_REGION} 2>/dev/null; then
    echo "Policy ${TIMESTREAM_POLICY_NAME} already exists, updating..."
    
    # Get current default version
    CURRENT_VERSION=$(aws iam get-policy \
        --policy-arn ${TIMESTREAM_POLICY_ARN} \
        --query 'Policy.DefaultVersionId' \
        --output text)
    
    # Create new version
    aws iam create-policy-version \
        --policy-arn ${TIMESTREAM_POLICY_ARN} \
        --policy-document "${TIMESTREAM_POLICY}" \
        --set-as-default
    
    # Delete old version
    aws iam delete-policy-version \
        --policy-arn ${TIMESTREAM_POLICY_ARN} \
        --version-id ${CURRENT_VERSION}
    
    echo "✓ Policy updated"
else
    echo "Creating new policy ${TIMESTREAM_POLICY_NAME}..."
    aws iam create-policy \
        --policy-name ${TIMESTREAM_POLICY_NAME} \
        --policy-document "${TIMESTREAM_POLICY}" \
        --description "Allows ECS tasks to access AWS Timestream database"
    
    echo "✓ Policy created"
fi

# Step 3: Attach policies to task role
echo ""
echo "Step 3: Attaching policies to task role..."

# Attach Bedrock policy
if aws iam list-attached-role-policies \
    --role-name ${TASK_ROLE_NAME} \
    --query "AttachedPolicies[?PolicyArn=='${BEDROCK_POLICY_ARN}']" \
    --output text | grep -q "${BEDROCK_POLICY_ARN}"; then
    echo "Bedrock policy already attached"
else
    echo "Attaching Bedrock policy..."
    aws iam attach-role-policy \
        --role-name ${TASK_ROLE_NAME} \
        --policy-arn ${BEDROCK_POLICY_ARN}
    echo "✓ Bedrock policy attached"
fi

# Attach Timestream policy
if aws iam list-attached-role-policies \
    --role-name ${TASK_ROLE_NAME} \
    --query "AttachedPolicies[?PolicyArn=='${TIMESTREAM_POLICY_ARN}']" \
    --output text | grep -q "${TIMESTREAM_POLICY_ARN}"; then
    echo "Timestream policy already attached"
else
    echo "Attaching Timestream policy..."
    aws iam attach-role-policy \
        --role-name ${TASK_ROLE_NAME} \
        --policy-arn ${TIMESTREAM_POLICY_ARN}
    echo "✓ Timestream policy attached"
fi

# Step 4: Verify policies are attached
echo ""
echo "Step 4: Verifying policies..."
echo ""
echo "Attached policies:"
aws iam list-attached-role-policies \
    --role-name ${TASK_ROLE_NAME} \
    --query 'AttachedPolicies[*].[PolicyName, PolicyArn]' \
    --output table

echo ""
echo "=================================================="
echo "✓ AWS Service Permissions Added!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Run ./scripts/deploy-ecs-complete.sh to update your ECS service"
echo "2. Wait 2-3 minutes for task to restart"
echo "3. Access your app and test Bedrock + Timestream"
echo "=================================================="
