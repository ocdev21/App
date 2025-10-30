FROM python:3.11-slim

WORKDIR /app

# Copy shared module first
COPY shared/ /app/shared/

# Copy requirements and install dependencies
COPY esapp/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY esapp/energy_19.py esapp/influxdb_example.py ./

# Make scripts executable
RUN chmod +x energy_19.py influxdb_example.py

# Run the InfluxDB-enabled application
CMD ["python", "-u", "influxdb_example.py"]
