#!/bin/bash

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
VPC_ID="${VPC_ID:-vpc-00f7e111e29a93774}"
SUBNET_1="${SUBNET_1:-subnet-0bf537354624ac176}"
SUBNET_2="${SUBNET_2:-subnet-0c1d10518b553764c}"

echo "=================================================="
echo "Debug: Creating ALB Components Step-by-Step"
echo "=================================================="
echo "VPC: ${VPC_ID}"
echo "Subnets: ${SUBNET_1}, ${SUBNET_2}"
echo ""

# Validate subnets are in different AZs
echo "Validating subnets..."
SUBNET_1_AZ=$(aws ec2 describe-subnets \
    --region ${AWS_REGION} \
    --subnet-ids ${SUBNET_1} \
    --query 'Subnets[0].AvailabilityZone' \
    --output text)

SUBNET_2_AZ=$(aws ec2 describe-subnets \
    --region ${AWS_REGION} \
    --subnet-ids ${SUBNET_2} \
    --query 'Subnets[0].AvailabilityZone' \
    --output text)

echo "Subnet 1 AZ: ${SUBNET_1_AZ}"
echo "Subnet 2 AZ: ${SUBNET_2_AZ}"

if [ "${SUBNET_1_AZ}" == "${SUBNET_2_AZ}" ]; then
    echo ""
    echo "ERROR: Both subnets are in the same availability zone!"
    echo "ALB requires subnets in at least 2 different AZs"
    exit 1
fi

echo "✓ Subnets are in different AZs"
echo ""

# Step 1: Check if ALB Security Group exists
echo "Step 1: Creating/Getting ALB Security Group..."
ALB_SG_ID=$(aws ec2 describe-security-groups \
    --region ${AWS_REGION} \
    --filters "Name=group-name,Values=superapp-alb-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [ "${ALB_SG_ID}" == "None" ] || [ -z "${ALB_SG_ID}" ]; then
    echo "Creating new security group..."
    ALB_SG_ID=$(aws ec2 create-security-group \
        --region ${AWS_REGION} \
        --group-name superapp-alb-sg \
        --description "Security group for SuperApp Application Load Balancer" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' \
        --output text)
    
    # Wait for security group to be available
    sleep 3
    
    # Allow HTTP traffic
    aws ec2 authorize-security-group-ingress \
        --region ${AWS_REGION} \
        --group-id ${ALB_SG_ID} \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
else
    echo "Security group already exists"
    # Try to add ingress rule (ignore if exists)
    aws ec2 authorize-security-group-ingress \
        --region ${AWS_REGION} \
        --group-id ${ALB_SG_ID} \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 2>/dev/null || echo "Ingress rule already exists"
fi

echo "✓ ALB Security Group: ${ALB_SG_ID}"
echo ""

# Step 2: Check if ALB already exists
echo "Step 2: Checking if ALB exists..."
EXISTING_ALB=$(aws elbv2 describe-load-balancers \
    --region ${AWS_REGION} \
    --query "LoadBalancers[?LoadBalancerName=='superapp-alb'].LoadBalancerArn" \
    --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_ALB}" ]; then
    echo "✓ ALB already exists: ${EXISTING_ALB}"
    ALB_ARN="${EXISTING_ALB}"
else
    echo "Creating new ALB..."
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --region ${AWS_REGION} \
        --name superapp-alb \
        --subnets ${SUBNET_1} ${SUBNET_2} \
        --security-groups ${ALB_SG_ID} \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags Key=Name,Value=superapp-alb \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    echo "✓ ALB Created: ${ALB_ARN}"
    
    # Wait for ALB to be active
    echo "Waiting for ALB to become active..."
    aws elbv2 wait load-balancer-available \
        --region ${AWS_REGION} \
        --load-balancer-arns ${ALB_ARN}
fi

# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region ${AWS_REGION} \
    --load-balancer-arns ${ALB_ARN} \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "✓ ALB DNS: ${ALB_DNS}"
echo ""
echo "=================================================="
echo "Success! ALB is ready"
echo "ALB ARN: ${ALB_ARN}"
echo "ALB DNS: ${ALB_DNS}"
echo "=================================================="
