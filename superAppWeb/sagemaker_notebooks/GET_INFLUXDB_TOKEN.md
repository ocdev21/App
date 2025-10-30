# How to Get Your InfluxDB Token

Your InfluxDB token is required to connect to AWS Timestream for InfluxDB. This guide shows you three ways to get it.

## Quick Info

- **Database:** superAppDB
- **Endpoint:** https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws
- **AWS Account:** 012351853258
- **Region:** us-east-1

---

## Method 1: AWS Timestream Console (Initial Setup)

If you just created your InfluxDB database, the token was displayed once during setup.

### Steps:

1. **Go to AWS Console**
   - Sign in to AWS Console
   - Navigate to: **Amazon Timestream** → **InfluxDB databases**
   - Region: **us-east-1**

2. **Find Your Database**
   - Look for your database endpoint in the list
   - Should see: `Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws`

3. **Retrieve Initial Token**
   - ⚠️ The initial admin token is shown **only once** during database creation
   - If you saved it, you're good to go!
   - If not, see Method 2 below to generate a new one

---

## Method 2: InfluxDB Web UI (Recommended)

Access the InfluxDB web interface to generate a new token.

### Steps:

1. **Open InfluxDB UI**
   - Go to: https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws
   - You should see the InfluxDB login page

2. **Log In**
   - Use your admin username and password
   - These were set when you created the database in AWS

3. **Navigate to API Tokens**
   - Click on **Data** in the left sidebar
   - Click on **API Tokens** (or **Tokens**)
   
4. **Generate New Token**
   - Click **Generate API Token** button
   - Select **All Access Token** (or custom permissions)
   - Give it a name like "sagemaker-testing"
   - Click **Save**

5. **Copy Token**
   - ⚠️ **IMPORTANT:** Copy the token immediately!
   - It will look something like:
     ```
     vPRwhatever1234randomCharacters5678moreStuff==
     ```
   - Store it somewhere safe (like AWS Secrets Manager)

---

## Method 3: AWS Secrets Manager (If Already Stored)

If you already ran the setup scripts, your token might be in Secrets Manager.

### Check with AWS CLI:

```bash
# Get the secret value
aws secretsmanager get-secret-value \
  --secret-id superapp-influxdb-credentials \
  --region us-east-1 \
  --query SecretString \
  --output text
```

This will return JSON like:
```json
{
  "INFLUXDB_URL": "https://...",
  "INFLUXDB_TOKEN": "your-token-here",
  "INFLUXDB_ORG": "superapp-org",
  "INFLUXDB_BUCKET": "test-bucket"
}
```

### Check with AWS Console:

1. Go to **AWS Secrets Manager** console
2. Region: **us-east-1**
3. Find secret: `superapp-influxdb-credentials`
4. Click **Retrieve secret value**
5. Copy the `INFLUXDB_TOKEN` value

---

## Method 4: AWS CLI (List DB Info)

Get information about your InfluxDB database:

```bash
# List all InfluxDB databases
aws timestream-influxdb list-db-instances \
  --region us-east-1

# Get details about your specific database
aws timestream-influxdb get-db-instance \
  --identifier <your-db-identifier> \
  --region us-east-1
```

**Note:** This won't give you the token directly, but it confirms your database exists.

---

## What Your Token Looks Like

InfluxDB tokens are long strings that look like:

```
vPRwhatever1234randomCharacters5678moreStuff==
```

- Starts with letters/numbers
- Usually ends with `==`
- Around 80-100 characters long
- Case-sensitive

---

## Storing Your Token Securely

### Option 1: AWS Secrets Manager (Best for Production)

```bash
# Store token in Secrets Manager
aws secretsmanager create-secret \
  --name superapp-influxdb-credentials \
  --description "InfluxDB credentials for superAppDB" \
  --secret-string '{
    "INFLUXDB_URL": "https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws",
    "INFLUXDB_TOKEN": "YOUR_TOKEN_HERE",
    "INFLUXDB_ORG": "superapp-org",
    "INFLUXDB_BUCKET": "test-bucket"
  }' \
  --region us-east-1
```

### Option 2: Environment Variables (Quick Testing)

```bash
export INFLUXDB_TOKEN="your-token-here"
export INFLUXDB_ORG="superapp-org"
export INFLUXDB_BUCKET="test-bucket"
```

### Option 3: Paste Directly in Notebook (Development Only)

In the SageMaker notebook:
```python
INFLUXDB_TOKEN = "your-token-here"  # ⚠️ Don't commit to git!
```

---

## Using Your Token in SageMaker

Once you have your token:

1. Open `influxdb_simple_test.ipynb`
2. Find **Step 3: Configure Your InfluxDB Connection**
3. Paste your token:
   ```python
   INFLUXDB_TOKEN = "vPRwhatever1234..."  # ⬅️ Paste here
   ```
4. Run the notebook!

---

## Troubleshooting

### "Invalid token" or "Unauthorized"
- Token might be wrong or expired
- Generate a new token using Method 2 (InfluxDB UI)
- Check you copied the entire token (including any `==` at the end)

### "Connection timeout" or "Cannot connect"
- Check the endpoint URL is correct
- Ensure your network allows HTTPS traffic to the endpoint
- Verify the database is running in AWS Console

### "Org not found"
- Check your organization name (`superapp-org`)
- View organizations in InfluxDB UI → Settings → Organizations

### "Bucket not found"
- The bucket might not exist yet
- Create bucket in InfluxDB UI → Data → Buckets
- Or update `INFLUXDB_BUCKET` in the notebook

---

## Important Security Notes

⚠️ **NEVER commit tokens to version control (Git)**
- Add `.env` files to `.gitignore`
- Use Secrets Manager for production
- Rotate tokens regularly

⚠️ **Token Permissions**
- Use least-privilege tokens (only read/write what's needed)
- Create separate tokens for different applications
- Revoke unused tokens

⚠️ **Token Rotation**
- Change tokens periodically
- Update Secrets Manager when you rotate
- Update all applications using the old token

---

## Need Help?

- **AWS Timestream Documentation:** https://docs.aws.amazon.com/timestream/
- **InfluxDB Documentation:** https://docs.influxdata.com/influxdb/
- **AWS Secrets Manager:** https://docs.aws.amazon.com/secretsmanager/

For issues with the notebook, see the main `README.md` in the `sagemaker_notebooks` folder.

---

**Quick Reference:**
- Database: `superAppDB`
- Endpoint: `https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws`
- Org: `superapp-org`
- Default Bucket: `test-bucket`
- Region: `us-east-1`
