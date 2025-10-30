# InfluxDB Testing Notebook - Quick Setup Guide

This guide will help you get started with the InfluxDB testing notebook (`03_influxdb_testing.ipynb`) in AWS SageMaker.

## Prerequisites

1. **AWS SageMaker Notebook Instance or Studio**
   - Instance type: `ml.t3.medium` or larger
   - Execution role with Bedrock and Secrets Manager permissions

2. **InfluxDB Endpoint**
   - AWS Timestream for InfluxDB: `https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws`
   - Database: `superAppDB`

3. **InfluxDB Credentials**
   - Stored in AWS Secrets Manager: `superapp-influxdb-credentials`
   - Or set as environment variables

## Step 1: Upload the Notebook

### Option A: Upload via SageMaker Console
1. Open SageMaker JupyterLab
2. Click the upload button (↑ icon)
3. Navigate to `sagemaker_notebooks/notebooks/`
4. Upload `03_influxdb_testing.ipynb`

### Option B: Clone from Git
```bash
cd ~/SageMaker
git clone <your-repo-url>
cd sagemaker_notebooks/notebooks
```

## Step 2: Install Dependencies

Open a terminal in JupyterLab and run:

```bash
pip install influxdb-client==1.49.0 boto3 pandas plotly ipywidgets aiohttp
```

Or install all SageMaker dependencies:

```bash
cd ~/SageMaker/sagemaker_notebooks
pip install -r requirements.txt
```

## Step 3: Configure Credentials

### Option A: Use AWS Secrets Manager (Recommended)

The notebook includes commented-out code to load credentials from Secrets Manager. Uncomment the code in section 2:

```python
# Load and update configuration
secrets = load_influxdb_credentials_from_secrets_manager()
if secrets:
    INFLUXDB_URL = secrets.get('INFLUXDB_URL', INFLUXDB_URL)
    INFLUXDB_TOKEN = secrets.get('INFLUXDB_TOKEN', INFLUXDB_TOKEN)
    INFLUXDB_ORG = secrets.get('INFLUXDB_ORG', INFLUXDB_ORG)
    INFLUXDB_BUCKET = secrets.get('INFLUXDB_BUCKET', INFLUXDB_BUCKET)
    print("✓ Credentials loaded from Secrets Manager")
```

### Option B: Set Environment Variables

```bash
export INFLUXDB_TOKEN="your-influxdb-token-here"
export INFLUXDB_ORG="superapp-org"
export INFLUXDB_BUCKET="test-bucket"
```

### Option C: Hard-code in Notebook (Development Only)

```python
INFLUXDB_TOKEN = "your-token-here"
INFLUXDB_ORG = "your-org"
INFLUXDB_BUCKET = "your-bucket"
```

**⚠️ Warning:** Never commit credentials to version control!

## Step 4: Run the Notebook

1. Open `03_influxdb_testing.ipynb`
2. Run cells sequentially using Shift+Enter
3. Or use "Run All" from the Cell menu

### Expected Output

**Section 1-3:** Setup and client initialization
- ✓ InfluxDB client connected
- ✓ AWS Bedrock client initialized
- ✓ Health check passed

**Section 4:** Test data writing
- ✓ Successfully wrote 20 energy metric points
- ✓ Successfully wrote 20 sensor data points

**Section 5:** Data visualization
- Interactive Plotly charts showing energy and sensor data

**Section 6:** AI Analysis
- Claude 3 analyzes your time-series data
- Provides insights and recommendations

**Section 7:** Interactive widgets
- Use dropdown menus and buttons to test different scenarios
- Write custom amounts of data
- Query different time ranges

**Section 8:** Performance testing
- Measures write throughput
- Measures query latency

## Notebook Sections Overview

| Section | Description | Interactive? |
|---------|-------------|--------------|
| 1-2 | Setup and configuration | No |
| 3 | Initialize clients | No |
| 4 | Write test data | No |
| 5 | Query and visualize | Yes (Plotly charts) |
| 6 | AI analysis with Claude 3 | No |
| 7 | Interactive testing widget | Yes (ipywidgets) |
| 8 | Performance testing | No |
| 9 | Cleanup | No |

## IAM Permissions Required

Your SageMaker execution role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel"
      ],
      "Resource": "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:012351853258:secret:superapp-influxdb-credentials-*"
    }
  ]
}
```

## Common Issues and Solutions

### Issue: "No module named 'influxdb_client'"
**Solution:** Install the package:
```bash
pip install influxdb-client==1.49.0
```

### Issue: "Token configured: No"
**Solution:** Set your InfluxDB token in the configuration section or load from Secrets Manager

### Issue: "Error loading secrets: AccessDeniedException"
**Solution:** Add Secrets Manager permissions to your SageMaker execution role

### Issue: "ConnectionError" or "Timeout"
**Solution:** 
- Check your InfluxDB endpoint URL is correct
- Ensure network connectivity to InfluxDB endpoint
- Verify security groups allow outbound HTTPS (443)

### Issue: Widgets not displaying
**Solution:**
```bash
jupyter nbextension enable --py widgetsnbextension
# Restart the Jupyter kernel
```

### Issue: "AccessDeniedException" from Bedrock
**Solution:**
- Enable Claude 3 model access in Bedrock Console
- Add Bedrock permissions to SageMaker execution role
- Use a supported region (us-east-1, us-west-2)

## Testing Different Scenarios

### Test 1: Write Energy Metrics
```python
write_sample_energy_metrics(count=50)
```

### Test 2: Query Last 24 Hours
```python
energy_df = query_energy_metrics(hours=24)
display(energy_df)
```

### Test 3: AI Analysis
```python
analysis = invoke_bedrock_claude("Analyze this data: " + str(energy_df.describe()))
print(analysis)
```

### Test 4: Performance Testing
```python
performance_test_write(num_points=1000)
performance_test_query()
```

## Advanced Usage

### Custom Measurements

Create your own data points:

```python
from influxdb_client import Point, WritePrecision

point = (
    Point("custom_measurement")
    .tag("location", "office")
    .tag("device", "sensor-1")
    .field("temperature", 22.5)
    .field("humidity", 45.0)
    .time(datetime.utcnow(), WritePrecision.NS)
)

write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=point)
```

### Custom Flux Queries

```python
flux_query = '''
from(bucket: "test-bucket")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "energy_metrics")
  |> aggregateWindow(every: 10m, fn: mean)
'''

tables = query_api.query(flux_query, org=INFLUXDB_ORG)
```

### Batch Writes

```python
points = []
for i in range(1000):
    point = Point("batch_test").field("value", i)
    points.append(point)

write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=points)
```

## Next Steps

1. ✅ Successfully run all notebook sections
2. ✅ Write custom test data
3. ✅ Experiment with different Flux queries
4. ✅ Use AI analysis for your own data
5. ⬜ Integrate with your production data pipelines
6. ⬜ Create automated monitoring dashboards
7. ⬜ Set up alerts based on thresholds

## Resources

- **InfluxDB Flux Documentation:** https://docs.influxdata.com/flux/
- **AWS Bedrock Claude 3:** https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-claude.html
- **InfluxDB Python Client:** https://github.com/influxdata/influxdb-client-python
- **Plotly Documentation:** https://plotly.com/python/

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the main README: `../README.md`
3. Check the deployment guides in the repository root

---

**AWS Account:** 012351853258  
**Region:** us-east-1  
**InfluxDB Database:** superAppDB  
**Last Updated:** October 30, 2025
