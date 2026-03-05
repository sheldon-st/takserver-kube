#!/bin/bash

NAMESPACE="tak"
RELEASE_NAME="tak-server"

echo "Uninstalling TAK server Helm release..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null

echo "Deleting PVCs..."
kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null

echo "Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null

echo "Removing local tak directory..."
rm -rf tak
rm -rf /tmp/takserver

echo "Removing Docker images (optional)..."
docker image rm tak-server-db --force 2>/dev/null
docker image rm tak-server --force 2>/dev/null

echo "Cleanup complete."
