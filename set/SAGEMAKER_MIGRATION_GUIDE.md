# AWS Integration Dashboard - SageMaker Migration Guide

## Overview

This guide explains how to migrate the AWS Integration Dashboard from a Node.js/React web application to AWS SageMaker JupyterHub notebooks.

## Migration Strategy

### Why Python?
- SageMaker Studio comes pre-configured with boto3 and AWS SDKs
- Better integration with SageMaker's execution roles
- Native Jupyter notebook support
- Rich data science ecosystem (pandas, plotly, ipywidgets)

### Architecture Changes

**Before (Web Application):**
- React frontend + Express backend
- Server-Sent Events for streaming
- REST API endpoints
- Browser-based UI

**After (SageMaker Notebooks):**
- Python modules for AWS integrations
- Jupyter notebooks with interactive widgets
- Direct boto3 SDK calls
- ipywidgets-based UI or Voila dashboard

## File Structure

```
sagemaker_notebooks/
├── requirements.txt                 # Python dependencies
├── setup_instructions.md            # SageMaker setup guide
├── modules/
│   ├── bedrock_streaming.py        # Claude 3 integration
│   └── timestream_client.py        # Timestream queries
├── notebooks/
│   ├── 00_setup.ipynb              # Environment validation & setup
│   ├── 01_claude_chat.ipynb        # Interactive Claude 3 chat
│   └── 02_timestream_dashboard.ipynb # Timestream data visualization
└── README.md                        # Quick start guide
```

## SageMaker Setup

### Step 1: Create SageMaker Notebook Instance

1. **Open AWS Console** → SageMaker → Notebook instances
2. **Create notebook instance:**
   - Name: `aws-integration-dashboard`
   - Instance type: `ml.t3.medium` (or larger)
   - Platform identifier: Amazon Linux 2, Jupyter Lab 3
   - IAM role: Create new or use existing with required permissions

3. **IAM Role Requirements:**
   Your SageMaker execution role needs these permissions:
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
         "Resource": "arn:aws:bedrock:*:012351853258:model/anthropic.claude-3-sonnet-20240229-v1:0"
       },
       {
         "Effect": "Allow",
         "Action": [
           "timestream:CreateDatabase",
           "timestream:CreateTable",
           "timestream:WriteRecords",
           "timestream:Select",
           "timestream:DescribeTable",
           "timestream:DescribeDatabase"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

4. **Network Settings:**
   - Enable internet access (for Bedrock API calls)
   - Or configure VPC with endpoints for Bedrock/Timestream

5. **Click "Create notebook instance"** and wait for status: InService

### Step 2: Upload Files to SageMaker

1. **Open JupyterLab** from the notebook instance
2. **Upload the following:**
   - Upload `modules/` folder
   - Upload `notebooks/` folder
   - Upload `requirements.txt`

3. **Or use git clone:**
   ```bash
   # In JupyterLab terminal
   cd SageMaker
   git clone <your-repo-url>
   ```

### Step 3: Install Dependencies

Open a terminal in JupyterLab and run:

```bash
cd ~/SageMaker
pip install -r requirements.txt
```

Required packages:
- `boto3` - AWS SDK (usually pre-installed)
- `ipywidgets` - Interactive widgets
- `pandas` - Data manipulation
- `plotly` - Visualizations
- `voila` (optional) - Dashboard deployment

### Step 4: Configure Environment Variables

Create a `.env` file or set environment variables:

```bash
export AWS_REGION=us-east-1
export TIMESTREAM_DATABASE_NAME=SuperAppDB
export AWS_ACCOUNT_ID=012351853258
```

**Note:** You don't need AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY when using SageMaker execution roles!

## Using the Notebooks

### Notebook 1: Setup & Validation (00_setup.ipynb)

**Purpose:** Validate your environment and AWS permissions

**What it does:**
- Checks boto3 installation
- Validates AWS credentials (via execution role)
- Tests Bedrock connectivity
- Creates Timestream database and UEReports table
- Displays configuration summary

**Run this first!**

### Notebook 2: Claude 3 Chat (01_claude_chat.ipynb)

**Purpose:** Interactive chat with Claude 3 AI

**Features:**
- Text input widget for prompts
- Real-time streaming response display
- Character counter (0-10,000 chars)
- Submit and Clear buttons
- Error handling with helpful messages

**How to use:**
1. Run all cells to initialize widgets
2. Enter your prompt in the text area
3. Click "Submit" to get streaming response
4. Watch the response appear word-by-word

### Notebook 3: Timestream Dashboard (02_timestream_dashboard.ipynb)

**Purpose:** Query and visualize Timestream data

**Features:**
- Query UEReports table
- Display results in pandas DataFrame
- Interactive table with filtering/sorting
- Visualizations with Plotly
- Refresh button to reload data
- Error handling for empty tables

**How to use:**
1. Run all cells
2. Click "Refresh Data" to query Timestream
3. View results in the table
4. Explore visualizations

## Migration Mapping

### Original Code → New Code

#### Bedrock Integration

**Original (TypeScript):**
```typescript
// server/aws/bedrock.ts
const command = new InvokeModelWithResponseStreamCommand({...});
const response = await client.send(command);
for await (const event of response.body) {
  if (event.chunk?.bytes) {
    const chunkData = JSON.parse(new TextDecoder().decode(event.chunk.bytes));
    onChunk(chunkData.delta.text);
  }
}
```

**New (Python):**
```python
# modules/bedrock_streaming.py
response = bedrock.invoke_model_with_response_stream(...)
for event in response['body']:
    chunk = json.loads(event['chunk']['bytes'])
    if chunk['type'] == 'content_block_delta':
        yield chunk['delta']['text']
```

#### Timestream Integration

**Original (TypeScript):**
```typescript
// server/aws/timestream.ts
const command = new QueryCommand({
  QueryString: "SELECT * FROM UEReports LIMIT 100"
});
const response = await client.send(command);
```

**New (Python):**
```python
# modules/timestream_client.py
response = timestream_query.query(
    QueryString="SELECT * FROM UEReports LIMIT 100"
)
df = parse_to_dataframe(response)
```

#### UI Components

**Original (React):**
```jsx
<Textarea value={prompt} onChange={...} />
<Button onClick={handleSubmit}>Submit</Button>
```

**New (Jupyter ipywidgets):**
```python
prompt_input = widgets.Textarea(...)
submit_btn = widgets.Button(description='Submit')
display(prompt_input, submit_btn)
```

## Advanced: Deploy as Voila Dashboard

Once your notebooks work well, you can convert them to a web dashboard:

1. **Install Voila:**
   ```bash
   pip install voila
   ```

2. **Run as dashboard:**
   ```bash
   voila 01_claude_chat.ipynb
   ```

3. **Access the dashboard:**
   - Opens on port 8866 by default
   - Use SageMaker's preview app feature

## Troubleshooting

### "AccessDeniedException" from Bedrock
- **Cause:** SageMaker execution role lacks Bedrock permissions
- **Fix:** Add `bedrock:InvokeModelWithResponseStream` permission to role
- **Check:** Run 00_setup.ipynb to validate permissions

### "ResourceNotFoundException" for Timestream
- **Cause:** Database/table doesn't exist
- **Fix:** Run 00_setup.ipynb to create database and table
- **Verify:** Check AWS Console → Timestream → Databases

### "No module named 'boto3'"
- **Cause:** Dependencies not installed
- **Fix:** Run `pip install -r requirements.txt` in terminal

### Widgets not displaying
- **Cause:** ipywidgets not enabled
- **Fix:** Run `jupyter nbextension enable --py widgetsnbextension`

### Streaming not working
- **Cause:** Network/firewall blocking Bedrock API
- **Fix:** Check notebook instance has internet access or VPC endpoints

## Cost Considerations

### SageMaker Costs
- **Notebook instance:** ~$0.05/hour for ml.t3.medium (on-demand)
- **Tip:** Stop instance when not in use to save costs

### Bedrock Costs
- **Claude 3 Sonnet:** ~$0.003 per 1K input tokens, ~$0.015 per 1K output tokens
- **Estimate:** $0.10-$0.50 per typical chat session

### Timestream Costs
- **Storage:** $0.03 per GB-month
- **Queries:** $0.01 per GB scanned
- **Estimate:** <$1/month for small datasets

## Next Steps

1. ✅ Create SageMaker notebook instance with proper IAM role
2. ✅ Upload files and install dependencies
3. ✅ Run 00_setup.ipynb to validate environment
4. ✅ Test Claude 3 chat in 01_claude_chat.ipynb
5. ✅ Explore Timestream data in 02_timestream_dashboard.ipynb
6. (Optional) Deploy as Voila dashboard for team access

## Comparison: Web App vs. SageMaker

| Feature | Web App | SageMaker Notebooks |
|---------|---------|---------------------|
| **Deployment** | Requires hosting | Built into AWS |
| **UI** | Professional React app | Widget-based or Voila |
| **Scaling** | Manual server scaling | Notebook instance size |
| **Credentials** | Manual env vars | Execution role (automatic) |
| **Cost** | Server 24/7 | Pay only when running |
| **Best For** | Public-facing apps | Internal data science work |

## Support

For issues or questions:
- Check troubleshooting section above
- Review AWS documentation for Bedrock/Timestream
- Ensure SageMaker execution role has correct permissions

---

**Migration completed by:** Replit Agent  
**Last updated:** October 29, 2025  
**AWS Account:** 012351853258
