#!/bin/bash

set -e

echo "=================================================="
echo "Adding Bedrock Invoke Permissions to IAM User"
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

# Create Bedrock invoke policy
echo ""
echo "Step 2: Creating Bedrock invoke policy..."

cat > /tmp/bedrock-invoke-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "*"
    }
  ]
}
EOF

echo "✓ Policy document created"

# Attach policy to user
echo ""
echo "Step 3: Attaching policy to user: $USERNAME..."

aws iam put-user-policy \
  --user-name "$USERNAME" \
  --policy-name BedrockInvokeAccess \
  --policy-document file:///tmp/bedrock-invoke-policy.json

echo "✓ Policy attached successfully"

# Clean up
rm -f /tmp/bedrock-invoke-policy.json

# Test the permissions
echo ""
echo "Step 4: Testing Bedrock invoke permissions..."
echo "Testing with Claude 3 Sonnet model..."

aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"messages":[{"role":"user","content":"Say hello in 5 words"}],"max_tokens":50,"anthropic_version":"bedrock-2023-05-31"}' \
  --region us-east-1 \
  /tmp/bedrock-test-response.json > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ Bedrock invoke test SUCCESSFUL!"
    echo ""
    echo "Response from Claude 3:"
    cat /tmp/bedrock-test-response.json | jq -r '.body' | base64 -d | jq -r '.content[0].text'
    rm -f /tmp/bedrock-test-response.json
else
    echo "❌ Bedrock invoke test FAILED"
    echo "The policy was attached, but you may need to wait a few seconds for IAM to propagate."
    echo "Try running this test manually in 30 seconds:"
    echo ""
    echo "aws bedrock-runtime invoke-model \\"
    echo "  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \\"
    echo "  --body '{\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"max_tokens\":100,\"anthropic_version\":\"bedrock-2023-05-31\"}' \\"
    echo "  --region us-east-1 \\"
    echo "  /tmp/response.json && cat /tmp/response.json"
fi

echo ""
echo "=================================================="
echo "✓ Setup Complete!"
echo "=================================================="
echo ""
echo "Your IAM user '$USERNAME' now has:"
echo "  • bedrock:InvokeModel"
echo "  • bedrock:InvokeModelWithResponseStream"
echo ""
echo "You can now:"
echo "  • Use Bedrock Playground in AWS Console"
echo "  • Deploy the SuperApp to ECS"
echo "  • Test locally with AWS credentials"
echo "=================================================="
