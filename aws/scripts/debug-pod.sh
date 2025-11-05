#!/bin/bash

NAMESPACE="l1-troubleshooting"

echo "=========================================="
echo "Pod Diagnostics"
echo "=========================================="
echo ""

echo "1. Pod Status:"
kubectl get pods -n $NAMESPACE -l app=l1-troubleshooting

echo ""
echo "2. Pod Description:"
kubectl describe pod -l app=l1-troubleshooting -n $NAMESPACE | tail -50

echo ""
echo "3. Container Logs (if available):"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=l1-troubleshooting -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$POD_NAME" ]; then
    echo "Pod: $POD_NAME"
    echo ""
    echo "Main container logs:"
    kubectl logs $POD_NAME -n $NAMESPACE --tail=100 2>&1 || echo "No logs available yet"
    
    echo ""
    echo "Previous container logs (if crashed):"
    kubectl logs $POD_NAME -n $NAMESPACE --previous --tail=100 2>&1 || echo "No previous logs"
else
    echo "No pod found"
fi

echo ""
echo "=========================================="
