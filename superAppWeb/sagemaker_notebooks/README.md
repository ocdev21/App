# AWS Integration Dashboard for SageMaker

Complete Python implementation of the AWS Integration Dashboard for AWS SageMaker JupyterHub.

## Quick Start

### 1. Upload to SageMaker

1. Create a SageMaker notebook instance (or use SageMaker Studio)
2. Open JupyterLab
3. Upload this entire `sagemaker_notebooks` folder
4. Or clone from git:
   ```bash
   cd ~/SageMaker
   git clone <your-repo-url>
   cd sagemaker_notebooks
   ```

### 2. Install Dependencies

Open a terminal in JupyterLab and run:

```bash
cd ~/SageMaker/sagemaker_notebooks
pip install -r requirements.txt
```

### 3. Run the Notebooks

Open notebooks in this order:

1. **`00_setup.ipynb`** - Validates environment and creates Timestream database
2. **`01_claude_chat.ipynb`** - Interactive Claude 3 AI chat
3. **`02_timestream_dashboard.ipynb`** - Timestream data visualization

## File Structure

```
sagemaker_notebooks/
├── README.md                        # This file
├── requirements.txt                 # Python dependencies
├── modules/
│   ├── bedrock_streaming.py        # Claude 3 integration module
│   └── timestream_client.py        # Timestream database module
└── notebooks/
    ├── 00_setup.ipynb              # Environment validation
    ├── 01_claude_chat.ipynb        # Claude 3 chat interface
    └── 02_timestream_dashboard.ipynb # Timestream dashboard
```

## Features

### Claude 3 Chat
- Real-time streaming responses from Claude 3
- Interactive widgets (no coding required!)
- Character counter (0-10,000 limit)
- Error handling with helpful messages

### Timestream Dashboard
- Query time-series data
- Interactive pandas DataFrame display
- Automatic visualizations with Plotly
- Add sample data for testing
- Export to CSV

## IAM Permissions Required

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
      "Resource": "arn:aws:bedrock:*::model/anthropic.claude-3-sonnet-20240229-v1:0"
    },
    {
      "Effect": "Allow",
      "Action": [
        "timestream:CreateDatabase",
        "timestream:CreateTable",
        "timestream:WriteRecords",
        "timestream:Select",
        "timestream:DescribeTable"
      ],
      "Resource": "*"
    }
  ]
}
```

## Configuration

Set environment variables (optional):

```bash
export AWS_REGION=us-east-1
export TIMESTREAM_DATABASE_NAME=SuperAppDB
```

Or modify directly in the notebooks.

## Troubleshooting

### "AccessDeniedException" from Bedrock
- Add Bedrock permissions to your SageMaker execution role
- Ensure Claude 3 model access is enabled in your AWS account
- Check you're in a supported region (us-east-1 or us-west-2)

### "ResourceNotFoundException" for Timestream
- Run `00_setup.ipynb` to create the database and table
- Check Timestream is available in your region

### Widgets not displaying
- Run: `jupyter nbextension enable --py widgetsnbextension`
- Restart the Jupyter kernel

### Import errors
- Make sure you installed dependencies: `pip install -r requirements.txt`
- Check the `modules/` folder is in the same directory as `notebooks/`

## Comparison to Web App

| Feature | Web App | SageMaker Notebooks |
|---------|---------|---------------------|
| **UI** | Professional React interface | Interactive widgets |
| **Deployment** | Requires server hosting | Built into SageMaker |
| **Credentials** | Manual environment variables | Execution role (automatic) |
| **Cost** | Server runs 24/7 | Pay only when running |
| **Best For** | Public-facing applications | Internal data science work |

## Next Steps

1. ✅ Run `00_setup.ipynb` to validate environment
2. ✅ Try Claude 3 chat in `01_claude_chat.ipynb`
3. ✅ Explore Timestream data in `02_timestream_dashboard.ipynb`
4. (Optional) Deploy as Voila dashboard for team access

## Support

For detailed setup instructions, see:
- `../SAGEMAKER_MIGRATION_GUIDE.md` - Complete migration guide
- `../IAM_ROLES_SETUP.md` - IAM permissions setup

---

**Migrated from:** Node.js/React web application  
**AWS Account:** 012351853258  
**Last Updated:** October 29, 2025
