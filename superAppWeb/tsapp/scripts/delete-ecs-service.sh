#!/bin/bash

set -e

echo "=================================================="
echo "TSApp - Delete ECS Service"
echo "=================================================="
echo ""

# Configuration
AWS_REGION="us-east-1"
CLUSTER_NAME="superapp-cluster"
SERVICE_NAME="tsapp-service"

echo "Checking if service exists..."
SERVICE_STATUS=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].status' \
  --output text 2>/dev/null)

if [ "$SERVICE_STATUS" == "None" ] || [ -z "$SERVICE_STATUS" ]; then
  echo "✓ Service does not exist. Nothing to delete."
else
  echo "Service status: $SERVICE_STATUS"
  echo "Deleting service..."
  
  aws ecs delete-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force \
    --region $AWS_REGION
  
  echo "✓ Service deleted"
  echo ""
  echo "Waiting 10 seconds for cleanup..."
  sleep 10
  echo "✓ Ready to create a new service"
fi

echo ""
echo "=================================================="
echo "✓ DONE!"
echo "=================================================="
echo ""
echo "Now you can run: ./scripts/create-ecs-service.sh"
