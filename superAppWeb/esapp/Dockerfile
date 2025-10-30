FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY energy_19.py .

# Make script executable
RUN chmod +x energy_19.py

# Run the application
CMD ["python", "-u", "energy_19.py"]
