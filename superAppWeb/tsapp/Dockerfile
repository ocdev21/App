FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY code_37.py .

# Make script executable
RUN chmod +x code_37.py

# Run the application
CMD ["python", "-u", "code_37.py"]
