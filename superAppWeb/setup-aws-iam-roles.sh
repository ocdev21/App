#!/bin/bash

###############################################################################
# AWS IAM Role Automation Script for SuperApp
# Creates IAM roles with "superapp" prefix for Bedrock and Timestream access
# AWS Account: 012351853258
# 
# Usage: ./setup-aws-iam-roles.sh
# 
# Prerequisites:
#   - AWS CLI installed and configured
#   - Credentials with IAM permissions (CreateRole, CreatePolicy, AttachRolePolicy)
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=""

###############################################################################
# Utility Functions
###############################################################################

echo_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

echo_success() {
    echo -e "${GREEN}✓${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

error_exit() {
    echo_error "$1"
    exit 1
}

###############################################################################
# Validate Prerequisites
###############################################################################

validate_prerequisites() {
    echo_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first: https://aws.amazon.com/cli/"
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
        error_exit "Failed to get AWS account ID. Please configure AWS CLI credentials."
    
    echo_success "AWS CLI is configured"
    echo_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    echo_info "AWS Region: ${AWS_REGION}"
    echo ""
}

###############################################################################
# Create Trust Policies
###############################################################################

create_trust_policies() {
    echo_info "Creating trust policy documents..."
    
    # Trust policy for SageMaker execution role
    cat > /tmp/sagemaker-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "sagemaker.amazonaws.com",
          "ec2.amazonaws.com",
          "lambda.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    echo_success "Trust policies created"
}

###############################################################################
# Create IAM Policies
###############################################################################

create_bedrock_policy() {
    echo_info "Creating Bedrock access policy..."
    
    # Create Bedrock policy document
    cat > /tmp/bedrock-policy.json << 'EOF'
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
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-*"
      ]
    }
  ]
}
EOF
    
    # Check if policy already exists
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/superapp-bedrock-policy"
    if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
        echo_warning "Policy superapp-bedrock-policy already exists. Skipping creation."
        return 0
    fi
    
    # Create the policy
    aws iam create-policy \
        --policy-name "superapp-bedrock-policy" \
        --description "Allows access to AWS Bedrock Claude 3 models" \
        --policy-document file:///tmp/bedrock-policy.json \
        --output text &>/dev/null || error_exit "Failed to create Bedrock policy"
    
    echo_success "Bedrock policy created: ${POLICY_ARN}"
}

create_timestream_write_policy() {
    echo_info "Creating Timestream write policy..."
    
    # Create Timestream write policy document
    cat > /tmp/timestream-write-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:CreateDatabase",
        "timestream:DescribeDatabase",
        "timestream:CreateTable",
        "timestream:DescribeTable",
        "timestream:WriteRecords",
        "timestream:UpdateTable"
      ],
      "Resource": "*"
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
    
    # Check if policy already exists
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/superapp-timestream-write-policy"
    if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
        echo_warning "Policy superapp-timestream-write-policy already exists. Skipping creation."
        return 0
    fi
    
    # Create the policy
    aws iam create-policy \
        --policy-name "superapp-timestream-write-policy" \
        --description "Allows write access to AWS Timestream database" \
        --policy-document file:///tmp/timestream-write-policy.json \
        --output text &>/dev/null || error_exit "Failed to create Timestream write policy"
    
    echo_success "Timestream write policy created: ${POLICY_ARN}"
}

create_timestream_query_policy() {
    echo_info "Creating Timestream query policy..."
    
    # Create Timestream query policy document
    cat > /tmp/timestream-query-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:DescribeDatabase",
        "timestream:DescribeTable",
        "timestream:Select",
        "timestream:SelectValues",
        "timestream:ListDatabases",
        "timestream:ListTables"
      ],
      "Resource": "*"
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
    
    # Check if policy already exists
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/superapp-timestream-query-policy"
    if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
        echo_warning "Policy superapp-timestream-query-policy already exists. Skipping creation."
        return 0
    fi
    
    # Create the policy
    aws iam create-policy \
        --policy-name "superapp-timestream-query-policy" \
        --description "Allows query access to AWS Timestream database" \
        --policy-document file:///tmp/timestream-query-policy.json \
        --output text &>/dev/null || error_exit "Failed to create Timestream query policy"
    
    echo_success "Timestream query policy created: ${POLICY_ARN}"
}

###############################################################################
# Create IAM Roles
###############################################################################

create_role_with_policy() {
    local role_name=$1
    local role_description=$2
    local policy_name=$3
    
    echo_info "Creating role: ${role_name}..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${role_name}" &>/dev/null; then
        echo_warning "Role ${role_name} already exists. Skipping creation."
    else
        # Create the role
        ROLE_ARN=$(aws iam create-role \
            --role-name "${role_name}" \
            --assume-role-policy-document file:///tmp/sagemaker-trust-policy.json \
            --description "${role_description}" \
            --max-session-duration 43200 \
            --tags Key=Project,Value=SuperApp Key=CreatedBy,Value=Automation Key=CreatedAt,Value=$(date +%Y-%m-%d) \
            --output text \
            --query 'Role.Arn') || error_exit "Failed to create role ${role_name}"
        
        echo_success "Role created: ${ROLE_ARN}"
    fi
    
    # Attach policy to role
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    echo_info "Attaching policy ${policy_name} to ${role_name}..."
    
    aws iam attach-role-policy \
        --role-name "${role_name}" \
        --policy-arn "${POLICY_ARN}" || error_exit "Failed to attach policy to ${role_name}"
    
    echo_success "Policy attached to ${role_name}"
    echo ""
}

###############################################################################
# Create SageMaker Execution Role
###############################################################################

create_sagemaker_execution_role() {
    local role_name="superapp-sagemaker-execution"
    
    echo_info "Creating comprehensive SageMaker execution role: ${role_name}..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${role_name}" &>/dev/null; then
        echo_warning "Role ${role_name} already exists. Updating policies..."
    else
        # Create the role
        ROLE_ARN=$(aws iam create-role \
            --role-name "${role_name}" \
            --assume-role-policy-document file:///tmp/sagemaker-trust-policy.json \
            --description "SageMaker execution role with Bedrock and Timestream access" \
            --max-session-duration 43200 \
            --tags Key=Project,Value=SuperApp Key=CreatedBy,Value=Automation Key=CreatedAt,Value=$(date +%Y-%m-%d) \
            --output text \
            --query 'Role.Arn') || error_exit "Failed to create SageMaker execution role"
        
        echo_success "Role created: ${ROLE_ARN}"
    fi
    
    # Attach all necessary policies
    echo_info "Attaching policies to SageMaker execution role..."
    
    # Bedrock policy
    aws iam attach-role-policy \
        --role-name "${role_name}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/superapp-bedrock-policy"
    
    # Timestream write policy
    aws iam attach-role-policy \
        --role-name "${role_name}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/superapp-timestream-write-policy"
    
    # Timestream query policy
    aws iam attach-role-policy \
        --role-name "${role_name}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/superapp-timestream-query-policy"
    
    # AWS managed SageMaker execution policy
    aws iam attach-role-policy \
        --role-name "${role_name}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" || true
    
    echo_success "All policies attached to SageMaker execution role"
    echo ""
}

###############################################################################
# Verify Setup
###############################################################################

verify_setup() {
    echo_info "Verifying IAM role setup..."
    echo ""
    
    local roles=(
        "superapp-bedrock-access"
        "superapp-timestream-write"
        "superapp-timestream-query"
        "superapp-sagemaker-execution"
    )
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "${role}" &>/dev/null; then
            ROLE_ARN=$(aws iam get-role --role-name "${role}" --query 'Role.Arn' --output text)
            echo_success "${role}"
            echo "           ARN: ${ROLE_ARN}"
            
            # List attached policies
            echo "           Policies:"
            aws iam list-attached-role-policies --role-name "${role}" --query 'AttachedPolicies[*].PolicyName' --output text | \
                tr '\t' '\n' | sed 's/^/             - /'
            echo ""
        else
            echo_error "${role} - NOT FOUND"
        fi
    done
}

###############################################################################
# Cleanup temporary files
###############################################################################

cleanup() {
    echo_info "Cleaning up temporary files..."
    rm -f /tmp/sagemaker-trust-policy.json
    rm -f /tmp/bedrock-policy.json
    rm -f /tmp/timestream-write-policy.json
    rm -f /tmp/timestream-query-policy.json
    echo_success "Cleanup complete"
}

###############################################################################
# Main Execution
###############################################################################

main() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "  SuperApp IAM Role Setup Script"
    echo "==========================================${NC}"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    
    # Create trust policies
    create_trust_policies
    echo ""
    
    # Create IAM policies
    echo -e "${BLUE}Creating IAM Policies...${NC}"
    create_bedrock_policy
    create_timestream_write_policy
    create_timestream_query_policy
    echo ""
    
    # Wait for policies to propagate
    echo_info "Waiting for policies to propagate (5 seconds)..."
    sleep 5
    echo ""
    
    # Create IAM roles
    echo -e "${BLUE}Creating IAM Roles...${NC}"
    create_role_with_policy "superapp-bedrock-access" \
        "Allows access to AWS Bedrock Claude 3 models" \
        "superapp-bedrock-policy"
    
    create_role_with_policy "superapp-timestream-write" \
        "Allows write access to AWS Timestream database" \
        "superapp-timestream-write-policy"
    
    create_role_with_policy "superapp-timestream-query" \
        "Allows query access to AWS Timestream database" \
        "superapp-timestream-query-policy"
    
    # Create comprehensive SageMaker execution role
    create_sagemaker_execution_role
    
    # Wait for roles to propagate
    echo_info "Waiting for roles to propagate (5 seconds)..."
    sleep 5
    echo ""
    
    # Verify setup
    echo -e "${BLUE}=========================================="
    echo "  Verification"
    echo "==========================================${NC}"
    echo ""
    verify_setup
    
    # Cleanup
    cleanup
    
    # Success message
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓ Setup Complete!"
    echo "==========================================${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Use 'superapp-sagemaker-execution' as your SageMaker notebook execution role"
    echo "2. This role has all necessary permissions for Bedrock and Timestream"
    echo "3. Run the Jupyter notebooks in sagemaker_notebooks/"
    echo ""
    echo -e "${YELLOW}Note:${NC} Role ARNs are displayed above. Save them for reference."
    echo ""
}

# Handle script interruption
trap cleanup EXIT INT TERM

# Run main function
main
