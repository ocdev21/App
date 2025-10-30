#!/bin/bash

set -e

echo "=================================================="
echo "Adding AWS Marketplace Permissions"
echo "=================================================="
echo ""

# Get current IAM user
echo "Step 1: Detecting current IAM user..."
USER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
USER_TYPE=$(echo $USER_ARN | cut -d':' -f6 | cut -d'/' -f1)

if [ "$USER_TYPE" == "user" ]; then
    USERNAME=$(echo $USER_ARN | cut -d'/' -f2)
    echo "✓ Detected IAM user: $USERNAME"
elif [ "$USER_TYPE" == "assumed-role" ]; then
    echo "❌ ERROR: You are using an assumed role, not an IAM user."
    echo "   This script only works for IAM users."
    echo "   Current identity: $USER_ARN"
    exit 1
else
    echo "❌ ERROR: Could not determine user type."
    echo "   Current identity: $USER_ARN"
    exit 1
fi

# Create marketplace policy
echo ""
echo "Step 2: Creating AWS Marketplace access policy..."

cat > /tmp/marketplace-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "aws-marketplace:Subscribe",
        "aws-marketplace:Unsubscribe",
        "aws-marketplace:ViewSubscriptions"
      ],
      "Resource": "*"
    }
  ]
}
EOF

echo "✓ Policy document created"

# Attach policy to user
echo ""
echo "Step 3: Attaching marketplace policy to user: $USERNAME..."

aws iam put-user-policy \
  --user-name "$USERNAME" \
  --policy-name MarketplaceAccess \
  --policy-document file:///tmp/marketplace-policy.json

echo "✓ Policy attached successfully"

# Clean up
rm -f /tmp/marketplace-policy.json

# Wait for IAM propagation
echo ""
echo "Step 4: Waiting 10 seconds for IAM to propagate..."
sleep 10

# Test Bedrock access
echo ""
echo "Step 5: Testing Bedrock access..."
echo "Attempting to invoke Claude 3 Sonnet..."

aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":50,"anthropic_version":"bedrock-2023-05-31"}' \
  --region us-east-1 \
  /tmp/bedrock-test.json > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ Bedrock test SUCCESSFUL!"
    echo ""
    echo "Response from Claude 3:"
    cat /tmp/bedrock-test.json | jq -r '.body' | base64 -d | jq -r '.content[0].text'
    rm -f /tmp/bedrock-test.json
    
    echo ""
    echo "=================================================="
    echo "✓ SUCCESS! Bedrock is now working!"
    echo "=================================================="
    echo ""
    echo "You can now:"
    echo "  • Use Bedrock Playground in AWS Console"
    echo "  • Deploy SuperApp to ECS"
    echo "  • Test locally with AWS credentials"
else
    echo "❌ Bedrock test still failing"
    echo ""
    echo "The marketplace permissions were added, but Bedrock still doesn't work."
    echo ""
    echo "Next steps to try:"
    echo "  1. Test with root account in AWS Console"
    echo "  2. Launch a t2.nano EC2 instance for 15 minutes (account validation)"
    echo "  3. Open AWS support case under 'Account Activation'"
    echo ""
    echo "Manual test command:"
    echo "aws bedrock-runtime invoke-model \\"
    echo "  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \\"
    echo "  --body '{\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"max_tokens\":100,\"anthropic_version\":\"bedrock-2023-05-31\"}' \\"
    echo "  --region us-east-1 \\"
    echo "  /tmp/response.json && cat /tmp/response.json"
fi

echo "=================================================="
