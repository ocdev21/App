FROM python:3.11-slim

WORKDIR /app

# Copy shared module first
COPY shared/ /app/shared/

# Copy requirements and install dependencies
COPY tsapp/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY tsapp/code_37.py tsapp/influxdb_example.py ./

# Make scripts executable
RUN chmod +x code_37.py influxdb_example.py

# Run the InfluxDB-enabled application
CMD ["python", "-u", "influxdb_example.py"]
