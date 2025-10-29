# IAM Roles Setup Guide for AWS Account 012351853258

This document provides instructions for creating IAM roles with the `superapp` prefix for AWS services integration.

## Required IAM Roles

### 1. superapp-bedrock-access
**Purpose**: Allows application to invoke Claude 3 models via AWS Bedrock

**Permissions Policy**:
```json
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
        "arn:aws:bedrock:*:012351853258:foundation-model/anthropic.claude-3-sonnet-*",
        "arn:aws:bedrock:*:012351853258:foundation-model/anthropic.claude-3-haiku-*",
        "arn:aws:bedrock:*:012351853258:foundation-model/anthropic.claude-3-opus-*"
      ]
    }
  ]
}
```

**Trust Relationship** (if using EC2/ECS):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 2. superapp-timestream-admin
**Purpose**: Allows application to create/manage Timestream databases and tables

**Permissions Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:CreateDatabase",
        "timestream:DescribeDatabase",
        "timestream:DeleteDatabase",
        "timestream:ListDatabases",
        "timestream:CreateTable",
        "timestream:DescribeTable",
        "timestream:DeleteTable",
        "timestream:ListTables",
        "timestream:UpdateTable",
        "timestream:WriteRecords",
        "timestream:DescribeEndpoints"
      ],
      "Resource": [
        "arn:aws:timestream:*:012351853258:database/*"
      ]
    }
  ]
}
```

### 3. superapp-timestream-query
**Purpose**: Allows application to query Timestream databases

**Permissions Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:Select",
        "timestream:DescribeEndpoints",
        "timestream:SelectValues",
        "timestream:DescribeTable"
      ],
      "Resource": [
        "arn:aws:timestream:*:012351853258:database/*/table/*"
      ]
    }
  ]
}
```

### 4. superapp-s3-access (Optional - for future use)
**Purpose**: Allows application to read/write to S3 buckets

**Permissions Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::superapp-*",
        "arn:aws:s3:::superapp-*/*"
      ]
    }
  ]
}
```

## Setup Instructions

### Creating IAM Roles via AWS Console

1. **Navigate to IAM**
   - Go to AWS Console → IAM → Roles → Create Role

2. **Select Trusted Entity**
   - For EC2/ECS deployment: Choose "AWS Service" → "EC2" or "ECS Task"
   - For programmatic access: Choose "AWS Account" → This account (012351853258)

3. **Attach Permissions**
   - Click "Create policy"
   - Switch to JSON tab
   - Paste the policy from above
   - Name the policy: `superapp-bedrock-policy`, `superapp-timestream-admin-policy`, etc.

4. **Name the Role**
   - Role name: `superapp-bedrock-access`, `superapp-timestream-admin`, etc.
   - Add description: "Allows SuperApp to access AWS Bedrock/Timestream"
   - Add tags:
     - `Application: SuperApp`
     - `Environment: Production`

5. **Review and Create**

### Creating IAM Roles via AWS CLI

```bash
# Create Bedrock access role
aws iam create-role \
  --role-name superapp-bedrock-access \
  --assume-role-policy-document file://trust-policy.json \
  --description "Allows SuperApp to invoke Claude 3 models"

aws iam put-role-policy \
  --role-name superapp-bedrock-access \
  --policy-name superapp-bedrock-policy \
  --policy-document file://bedrock-policy.json

# Create Timestream admin role
aws iam create-role \
  --role-name superapp-timestream-admin \
  --assume-role-policy-document file://trust-policy.json \
  --description "Allows SuperApp to manage Timestream databases"

aws iam put-role-policy \
  --role-name superapp-timestream-admin \
  --policy-name superapp-timestream-admin-policy \
  --policy-document file://timestream-admin-policy.json

# Create Timestream query role
aws iam create-role \
  --role-name superapp-timestream-query \
  --assume-role-policy-document file://trust-policy.json \
  --description "Allows SuperApp to query Timestream databases"

aws iam put-role-policy \
  --role-name superapp-timestream-query \
  --policy-name superapp-timestream-query-policy \
  --policy-document file://timestream-query-policy.json
```

## For Development (Access Keys)

For development purposes on Replit, you're using Access Keys instead of IAM roles. Ensure the IAM user has the following managed policies attached:

1. Create an IAM user: `superapp-dev-user`
2. Attach custom policies with the permissions listed above
3. Generate Access Keys
4. Add to Replit Secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION`

## Security Best Practices

1. **Principle of Least Privilege**: Only grant permissions that are absolutely necessary
2. **Rotate Credentials**: Regularly rotate access keys (every 90 days)
3. **Use IAM Roles**: For production EC2/ECS deployments, use IAM roles instead of access keys
4. **Enable MFA**: Require MFA for sensitive operations
5. **Audit Logs**: Enable CloudTrail to monitor all IAM actions
6. **Tag Resources**: Use consistent tagging (Application: SuperApp, Environment: Production)

## Verification

Test the IAM permissions with:

```bash
# Test Bedrock access
aws bedrock list-foundation-models --region us-east-1

# Test Timestream access
aws timestream-write describe-endpoints --region us-east-1

# Test S3 access
aws s3 ls s3://superapp-bucket-name/
```

## Troubleshooting

**Access Denied Errors**:
- Verify IAM role/user has correct policies attached
- Check policy resource ARNs match your account ID (012351853258)
- Ensure region in ARN matches your configured AWS_REGION

**Bedrock Model Not Found**:
- Verify model is available in your region
- Some models require opt-in via Bedrock console
- Try regions: us-east-1, us-west-2

**Timestream Setup Issues**:
- Ensure both write and query permissions are granted
- Verify endpoints are accessible in your region
- Check VPC/network settings if using private endpoints
