#!/bin/bash

# Fix LoadBalancer subnet tagging for EKS Auto Mode
# Tags VPC subnets so AWS Load Balancer Controller can discover them

set -e

CLUSTER_NAME="aws-hack"
REGION="us-east-1"

echo "========================================="
echo "Fixing LoadBalancer Subnet Tags"
echo "========================================="

# Get VPC ID from cluster
echo "Getting VPC ID from EKS cluster..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC ID: $VPC_ID"

# Get all subnets in the VPC
echo ""
echo "Finding subnets in VPC..."
SUBNET_IDS=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)

if [ -z "$SUBNET_IDS" ]; then
    echo "Error: No subnets found in VPC $VPC_ID"
    exit 1
fi

echo "Found subnets: $SUBNET_IDS"

# Tag each subnet
echo ""
echo "Tagging subnets for LoadBalancer discovery..."
for SUBNET_ID in $SUBNET_IDS; do
    echo "  Tagging subnet: $SUBNET_ID"
    
    # Check if subnet is public or private
    ROUTE_TABLE=$(aws ec2 describe-route-tables --region $REGION \
        --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
        --query 'RouteTables[0].Routes[?GatewayId!=`local`].GatewayId' \
        --output text)
    
    if [[ $ROUTE_TABLE == igw-* ]]; then
        # Public subnet - tag for public ELB
        echo "    Type: Public"
        aws ec2 create-tags --region $REGION --resources $SUBNET_ID --tags \
            Key=kubernetes.io/role/elb,Value=1 \
            Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared
    else
        # Private subnet - tag for internal ELB
        echo "    Type: Private"
        aws ec2 create-tags --region $REGION --resources $SUBNET_ID --tags \
            Key=kubernetes.io/role/internal-elb,Value=1 \
            Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared
    fi
done

echo ""
echo "✓ Subnet tagging complete!"
echo ""
echo "Now delete and recreate the LoadBalancer service:"
echo "  kubectl delete svc l1-app-service -n l1-troubleshooting"
echo "  kubectl apply -f aws/kubernetes/l1-app-deployment.yaml"
echo ""
echo "The LoadBalancer should provision within 2-3 minutes"
