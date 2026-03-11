#!/bin/bash
set -euo pipefail

# Creates a client certificate, registers the user in TAK server, and builds
# an ATAK/iTAK data package.
#
# Usage: ./scripts/makeCert.sh <username> <server_address> [--admin]
#   --admin: grant admin privileges (required for web UI access on port 8443)

if [ $# -lt 2 ]; then
    echo "Usage: $0 <username> <server_address> [--admin]"
    echo ""
    echo "  e.g. $0 user3 192.168.1.100         # ATAK/iTAK client user"
    echo "  e.g. $0 user3 takserver.example.com  # ATAK/iTAK client user (domain)"
    echo "  e.g. $0 webadmin 192.168.1.100 --admin  # web UI admin user"
    echo ""
    echo "Options:"
    echo "  --admin   Grant admin privileges (needed to log into the web UI)"
    echo ""
    echo "The server address should match an existing server certificate."
    echo "If no server cert exists yet, generate one first inside the pod:"
    echo "  kubectl exec -n tak <pod> -- bash -c 'cd /opt/tak/certs && ./makeCert.sh server <address>'"
    exit 1
fi

USER="$1"
SERVER="$2"
ADMIN=false
if [ "${3:-}" = "--admin" ]; then
    ADMIN=true
fi

NAMESPACE="tak"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ─── Find TAK server pod ─────────────────────────────────────────────────────

TAK_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=takserver" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$TAK_POD" ]; then
    echo "ERROR: Could not find takserver pod in namespace '$NAMESPACE'."
    echo "  Is the cluster running? Check: kubectl get pods -n $NAMESPACE"
    exit 1
fi
echo "Found takserver pod: $TAK_POD"

# ─── Generate client certificate ─────────────────────────────────────────────

echo "Generating client certificate for $USER..."
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client $USER"
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "chown -R 1000:1000 /opt/tak/certs/"

# ─── Register user in TAK server ─────────────────────────────────────────────

echo "Registering user $USER in TAK server..."

# Generate a password for the account (required by UserManager even for cert-based auth)
USER_PWD=$(LC_ALL=C tr -dc '[:alpha:][:digit:]' < /dev/urandom | head -c 11 || true)
USER_PASSWORD="${USER_PWD}Meh1!"

if [ "$ADMIN" = true ]; then
    # Create admin user (can access web UI on port 8443)
    echo "  Creating admin account..."
    kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c \
        "cd /opt/tak && java -jar utils/UserManager.jar usermod -A -p '${USER_PASSWORD}' $USER"

    echo "  Registering certificate with admin privileges..."
    kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c \
        "cd /opt/tak && java -jar utils/UserManager.jar certmod -A certs/files/$USER.pem"
else
    # Create regular user (ATAK/iTAK connections only)
    echo "  Creating user account..."
    kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c \
        "cd /opt/tak && java -jar utils/UserManager.jar usermod -p '${USER_PASSWORD}' $USER"

    echo "  Registering certificate..."
    kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c \
        "cd /opt/tak && java -jar utils/UserManager.jar certmod certs/files/$USER.pem"
fi

# ─── Copy certs locally ──────────────────────────────────────────────────────

mkdir -p "$PROJECT_DIR/tak/certs/files"
kubectl cp "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/" "$PROJECT_DIR/tak/certs/files/"

# Verify required files exist
if [ ! -f "$PROJECT_DIR/tak/certs/files/$USER.p12" ]; then
    echo "ERROR: Client cert $USER.p12 was not created."
    exit 1
fi
if [ ! -f "$PROJECT_DIR/tak/certs/files/$SERVER.p12" ]; then
    echo "ERROR: Server cert $SERVER.p12 not found."
    echo "  The server certificate for '$SERVER' does not exist."
    echo "  Generate one first:"
    echo "    kubectl exec -n $NAMESPACE $TAK_POD -- bash -c 'cd /opt/tak/certs && ./makeCert.sh server $SERVER'"
    exit 1
fi

# ─── Build data package ──────────────────────────────────────────────────────

echo "Building data package for $USER @ $SERVER..."

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/server.pref" <<PREF
<?xml version='1.0' encoding='ASCII' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">TAK Server</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">$SERVER:8089:ssl</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
    <entry key="caLocation" class="class java.lang.String">cert/$SERVER.p12</entry>
    <entry key="caPassword" class="class java.lang.String">atakatak</entry>
    <entry key="clientPassword" class="class java.lang.String">atakatak</entry>
    <entry key="certificateLocation" class="class java.lang.String">cert/$USER.p12</entry>
  </preference>
</preferences>
PREF

cat > "$TMPDIR/manifest.xml" <<MANIFEST
<MissionPackageManifest version="2">
  <Configuration>
    <Parameter name="uid" value="tak-server-data-package"/>
    <Parameter name="name" value="$USER DP"/>
    <Parameter name="onReceiveDelete" value="true"/>
  </Configuration>
  <Contents>
    <Content ignore="false" zipEntry="certs\\server.pref"/>
    <Content ignore="false" zipEntry="certs\\$SERVER.p12"/>
    <Content ignore="false" zipEntry="certs\\$USER.p12"/>
  </Contents>
</MissionPackageManifest>
MANIFEST

zip -j "$PROJECT_DIR/tak/certs/files/$USER-$SERVER.dp.zip" \
    "$TMPDIR/manifest.xml" \
    "$TMPDIR/server.pref" \
    "$PROJECT_DIR/tak/certs/files/$SERVER.p12" \
    "$PROJECT_DIR/tak/certs/files/$USER.p12"

# Copy data package back into the PVC
kubectl cp "$PROJECT_DIR/tak/certs/files/" "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "-------------------------------------------------------------"
echo "Created client cert:   tak/certs/files/$USER.p12"
echo "Created data package:  tak/certs/files/$USER-$SERVER.dp.zip"
echo "-------------------------------------------------------------"
if [ "$ADMIN" = true ]; then
    echo ""
    echo "Web UI access:"
    echo "  1. Import $USER.p12 into your browser (password: atakatak)"
    echo "  2. Visit https://$SERVER:8443"
    echo "  3. Select the $USER certificate when prompted"
else
    echo ""
    echo "ATAK/iTAK setup:"
    echo "  Copy $USER-$SERVER.dp.zip to your device and import it."
    echo ""
    echo "NOTE: This is a regular user cert. For web UI access, use --admin."
fi
