#!/bin/bash

NAMESPACE="tak"
RELEASE_NAME="tak-server"

echo "Uninstalling TAK server Helm release..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null

echo "Deleting PVCs..."
kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null

echo "Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null

echo "Removing local tak directory and certs..."
rm -rf tak
rm -rf /tmp/takserver
rm -f admin.p12

echo "Removing Docker images (optional)..."
docker image rm tak-server-db --force 2>/dev/null
docker image rm tak-server --force 2>/dev/null

# Remove images from k3s containerd if present
if command -v k3s &>/dev/null || [ -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "Removing images from k3s containerd..."
    # Remove both short and fully-qualified names in case either was used
    sudo k3s ctr images rm tak-server:latest 2>/dev/null
    sudo k3s ctr images rm tak-server-db:latest 2>/dev/null
    sudo k3s ctr images rm docker.io/library/tak-server:latest 2>/dev/null
    sudo k3s ctr images rm docker.io/library/tak-server-db:latest 2>/dev/null
fi

echo "Cleanup complete."
