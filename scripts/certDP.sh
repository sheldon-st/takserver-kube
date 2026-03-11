#!/bin/bash
set -euo pipefail

# Creates an ATAK / iTAK data package containing CA, user cert, and user key.
# Usage: ./scripts/certDP.sh <IP> <username>

if [ $# -lt 2 ]; then
    echo "Usage: $0 <IP> <username>"
    echo "  e.g. $0 192.168.0.2 user1"
    exit 1
fi

IP="$1"
USER="$2"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Validate required cert files exist
if [ ! -f "$PROJECT_DIR/tak/certs/files/$IP.p12" ]; then
    echo "ERROR: Server cert not found: tak/certs/files/$IP.p12"
    exit 1
fi
if [ ! -f "$PROJECT_DIR/tak/certs/files/$USER.p12" ]; then
    echo "ERROR: User cert not found: tak/certs/files/$USER.p12"
    exit 1
fi

# Use a temp directory for intermediate files
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/server.pref" <<PREF
<?xml version='1.0' encoding='ASCII' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">TAK Server</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">$IP:8089:ssl</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
    <entry key="caLocation" class="class java.lang.String">cert/$IP.p12</entry>
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
    <Content ignore="false" zipEntry="certs\\$IP.p12"/>
    <Content ignore="false" zipEntry="certs\\$USER.p12"/>
  </Contents>
</MissionPackageManifest>
MANIFEST

zip -j "$PROJECT_DIR/tak/certs/files/$USER-$IP.dp.zip" \
    "$TMPDIR/manifest.xml" \
    "$TMPDIR/server.pref" \
    "$PROJECT_DIR/tak/certs/files/$IP.p12" \
    "$PROJECT_DIR/tak/certs/files/$USER.p12"

echo "Created data package: tak/certs/files/$USER-$IP.dp.zip"
