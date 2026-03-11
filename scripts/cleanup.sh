#!/bin/bash
set -euo pipefail

NAMESPACE="tak"
RELEASE_NAME="tak-server"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "============================================"
echo "  TAK Server Cleanup"
echo "============================================"
echo ""
echo "This will:"
echo "  - Uninstall the Helm release ($RELEASE_NAME)"
echo "  - Delete all PVCs in the $NAMESPACE namespace"
echo "  - Delete the $NAMESPACE namespace"
echo "  - Remove local tak/ directory, admin.p12, and /tmp/takserver"
echo "  - Remove Docker images (tak-server, tak-server-db)"
echo ""
echo "WARNING: All TAK server data will be permanently lost."
echo ""
read -r -p "Are you sure? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy] ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "[1/5] Uninstalling Helm release..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null && echo "  Done." || echo "  No release found (skipped)."

echo "[2/5] Deleting PVCs..."
kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null && echo "  Done." || echo "  No PVCs found (skipped)."

echo "[3/5] Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null && echo "  Done." || echo "  Namespace not found (skipped)."

echo "[4/5] Removing local files..."
rm -rf "$PROJECT_DIR/tak"
rm -rf /tmp/takserver
rm -f "$PROJECT_DIR/admin.p12"
echo "  Done."

echo "[5/5] Removing Docker images..."
docker image rm tak-server-db --force 2>/dev/null || true
docker image rm tak-server --force 2>/dev/null || true

if command -v k3s &>/dev/null || [ -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "  Removing images from k3s containerd..."
    sudo k3s ctr images rm tak-server:latest 2>/dev/null || true
    sudo k3s ctr images rm tak-server-db:latest 2>/dev/null || true
    sudo k3s ctr images rm docker.io/library/tak-server:latest 2>/dev/null || true
    sudo k3s ctr images rm docker.io/library/tak-server-db:latest 2>/dev/null || true
fi
echo "  Done."

echo ""
echo "Cleanup complete."
