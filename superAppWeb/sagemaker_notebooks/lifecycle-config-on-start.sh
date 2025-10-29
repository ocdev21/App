#!/bin/bash

set -e

# SageMaker Lifecycle Configuration - On-Start Script
# This script runs every time the notebook instance starts
# It automatically installs requirements.txt from the notebook directory

echo "Starting lifecycle configuration..."

# Navigate to the SageMaker home directory
cd /home/ec2-user/SageMaker

# Check if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "Found requirements.txt, installing dependencies..."
    
    # Install requirements using pip
    sudo -u ec2-user -i <<'EOF'
source /home/ec2-user/anaconda3/bin/activate python3
pip install -r /home/ec2-user/SageMaker/requirements.txt
echo "✓ Requirements installed successfully"
EOF
else
    echo "No requirements.txt found in /home/ec2-user/SageMaker"
    echo "Upload your requirements.txt to the root of SageMaker directory"
fi

echo "Lifecycle configuration complete"
