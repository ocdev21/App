#!/bin/bash

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="012351853258"

echo "=================================================="
echo "Fixing IAM Trust Policies for ECS"
echo "=================================================="

# Step 1: Fix superapp-ecs-execution role trust policy
echo ""
echo "Step 1: Updating superapp-ecs-execution trust policy..."

cat > /tmp/ecs-execution-trust-policy.json <<'EOF'
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

aws iam update-assume-role-policy \
    --role-name superapp-ecs-execution \
    --policy-document file:///tmp/ecs-execution-trust-policy.json

echo "✓ superapp-ecs-execution trust policy updated"

# Step 2: Fix superapp-sagemaker-execution role trust policy
echo ""
echo "Step 2: Updating superapp-sagemaker-execution trust policy..."

cat > /tmp/ecs-task-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs-tasks.amazonaws.com",
          "sagemaker.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam update-assume-role-policy \
    --role-name superapp-sagemaker-execution \
    --policy-document file:///tmp/ecs-task-trust-policy.json

echo "✓ superapp-sagemaker-execution trust policy updated"

# Wait for IAM changes to propagate
echo ""
echo "Waiting 15 seconds for IAM changes to propagate..."
sleep 15

# Cleanup
rm -f /tmp/ecs-execution-trust-policy.json
rm -f /tmp/ecs-task-trust-policy.json

echo ""
echo "=================================================="
echo "✓ IAM Trust Policies Fixed!"
echo "=================================================="
echo ""
echo "Both roles now allow ECS tasks to assume them:"
echo "  - superapp-ecs-execution"
echo "  - superapp-sagemaker-execution"
echo ""
echo "Next steps:"
echo "1. Re-deploy your ECS service:"
echo "   ./scripts/deploy-ecs-complete.sh"
echo ""
echo "2. The task should now start successfully"
echo "=================================================="
