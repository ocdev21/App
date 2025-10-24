# Using Red Hat UBI (Universal Base Image) - Best for OpenShift
# This image is from Red Hat's registry and works well in enterprise environments
FROM registry.access.redhat.com/ubi9/python-311:latest

# Alternative registries if needed:
# FROM quay.io/centos/python-311-centos9:latest
# FROM mcr.microsoft.com/devcontainers/python:3.11

WORKDIR /app

# Install kubectl using Red Hat/CentOS package manager (microdnf for UBI9)
RUN microdnf install -y \
    curl \
    tar \
    && curl -LO https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/ \
    && microdnf clean all

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY energy_19.py .

RUN chmod +x energy_19.py

ENV PYTHONUNBUFFERED=1

CMD ["python", "energy_19.py"]
