#!/bin/bash
echo "WARNING: UNAUTHENTICATED USERS CAN NOW FETCH *CERTIFICATES*. THIS IS RISKY"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$PROJECT_DIR/share"
cp "$PROJECT_DIR/tak/certs/files/"*.zip "$PROJECT_DIR/share/" 2>/dev/null
cd "$PROJECT_DIR/share" || exit 1
python3 -m http.server 12345
