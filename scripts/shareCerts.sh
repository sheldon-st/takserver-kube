#!/bin/bash
set -euo pipefail

# Copies certificates from the TAK server pod and serves them over HTTP.
# WARNING: Unauthenticated users can fetch certificates. Use only on trusted networks.
# Usage: ./scripts/shareCerts.sh

NAMESPACE="tak"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "WARNING: This serves certificates over unencrypted HTTP."
echo "Only use this on a trusted network. For secure transfer, use USB."
echo ""

# Find the takserver pod
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=takserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
    echo "ERROR: Could not find takserver pod in namespace '$NAMESPACE'."
    echo "  Is the cluster running? Check: kubectl get pods -n $NAMESPACE"
    exit 1
fi
echo "Found takserver pod: $POD"

# Copy certs from the pod
rm -rf "$PROJECT_DIR/share"
mkdir -p "$PROJECT_DIR/share"
echo "Copying certs from pod..."
if ! kubectl cp "$NAMESPACE/$POD:/opt/tak/certs/files/" "$PROJECT_DIR/share/"; then
    echo "ERROR: Failed to copy certs from pod."
    exit 1
fi

echo ""
echo "Serving certs at http://0.0.0.0:12345"
echo "Press Ctrl-C to stop."
cd "$PROJECT_DIR/share" || exit 1
python3 -m http.server 12345
