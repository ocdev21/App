
#!/bin/bash

echo "Creating L1 Application ConfigMap with source code"
echo "================================================"

NAMESPACE="l1-app-ai"

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Remove existing configmap if it exists
kubectl delete configmap l1-app-code-config -n $NAMESPACE 2>/dev/null || true

echo "Creating ConfigMap with application source code..."

# Create ConfigMap from current directory structure
kubectl create configmap l1-app-code-config \
  --from-file=client/ \
  --from-file=server/ \
  --from-file=shared/ \
  --from-file=package.json \
  --from-file=package-lock.json \
  --from-file=requirements_mistral.txt \
  --from-file=tsconfig.json \
  --from-file=vite.config.ts \
  --from-file=tailwind.config.ts \
  --from-file=postcss.config.js \
  --from-file=components.json \
  --from-file=drizzle.config.ts \
  -n $NAMESPACE

if [ $? -eq 0 ]; then
    echo "ConfigMap created successfully"
else
    echo "ERROR: Failed to create ConfigMap"
    exit 1
fi

echo "ConfigMap contents:"
kubectl get configmap l1-app-code-config -n $NAMESPACE -o yaml | head -20
