#!/bin/bash
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────

color() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        STARTCOLOR="\033[$2"
        ENDCOLOR="\033[0m"
    else
        STARTCOLOR="\e[$2"
        ENDCOLOR="\e[0m"
    fi
    export "$1"="$STARTCOLOR%b$ENDCOLOR"
}
color info 96m
color success 92m
color warning 93m
color danger 91m

# ─── Constants ────────────────────────────────────────────────────────────────

NAMESPACE="tak"
RELEASE_NAME="tak-server"
HELM_CHART_DIR="$(cd "$(dirname "$0")/../helm/tak-server" && pwd)"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ─── Introduction ─────────────────────────────────────────────────────────────

printf $success "\n========================================\n"
printf $success "  TAK Server Setup (Kubernetes / Helm)  \n"
printf $success "========================================\n\n"
printf $info "Before running this script:\n"
printf $info "  1. Download the official Docker release ZIP from https://tak.gov/products/tak-server\n"
printf $info "  2. Place the ZIP file in the tak-server project root directory\n\n"
printf $warning "Required tools: kubectl, helm, docker, unzip\n"

# ─── Step 1: Detect platform ─────────────────────────────────────────────────

detect_platform() {
    printf $info "\n[Step 1/10] Detecting platform...\n"
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)  PLATFORM="linux" ;;
        Darwin) PLATFORM="darwin" ;;
        *)
            printf $danger "ERROR: Unsupported OS: $OS (only Linux and macOS are supported)\n"
            exit 1
            ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  DOCKER_ARCH="amd64" ;;
        arm64|aarch64) DOCKER_ARCH="arm64" ;;
        *)
            printf $danger "ERROR: Unsupported architecture: $ARCH (only amd64 and arm64 are supported)\n"
            exit 1
            ;;
    esac

    printf $success "  Platform: $PLATFORM/$DOCKER_ARCH\n"
}

# ─── Step 2: Check prerequisites ─────────────────────────────────────────────

check_prerequisites() {
    printf $info "\n[Step 2/10] Checking prerequisites...\n"
    local missing=0

    for cmd in kubectl helm docker; do
        if ! command -v $cmd &>/dev/null; then
            printf $danger "  ERROR: Required tool '$cmd' is not installed.\n"
            missing=1
        else
            printf $success "  Found: $cmd\n"
        fi
    done

    if ! command -v unzip &>/dev/null && ! command -v 7z &>/dev/null; then
        printf $danger "  ERROR: Neither 'unzip' nor '7z' is installed. Install one to extract the release.\n"
        missing=1
    else
        printf $success "  Found: unzip/7z\n"
    fi

    if [ $missing -eq 1 ]; then
        printf $danger "\nPlease install the missing tools listed above and try again.\n"
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        printf $danger "\n  ERROR: Cannot connect to a Kubernetes cluster.\n"
        printf $info "  Ensure kubectl is configured. For local development, use:\n"
        printf $info "    - Docker Desktop with Kubernetes enabled\n"
        printf $info "    - minikube (minikube start --memory 4096)\n"
        printf $info "    - kind (kind create cluster)\n"
        exit 1
    fi

    printf $success "  Connected to Kubernetes cluster.\n"
}

# ─── Step 3: Check ports ─────────────────────────────────────────────────────

port_check() {
    printf $info "\n[Step 3/10] Checking port availability...\n"
    local ports=(8089 8443 8444 8446 9000 9001)
    local conflicts=0

    for port in "${ports[@]}"; do
        if command -v lsof &>/dev/null; then
            if lsof -i :"$port" &>/dev/null; then
                printf $warning "  Port $port is in use (may conflict with NodePort services)\n"
                conflicts=1
            fi
        elif command -v ss &>/dev/null; then
            if ss -ltn | grep -q ":${port} " 2>/dev/null; then
                printf $warning "  Port $port is in use (may conflict with NodePort services)\n"
                conflicts=1
            fi
        fi
    done

    if [ $conflicts -eq 0 ]; then
        printf $success "  All required ports are available.\n"
    fi
}

# ─── Step 4: Handle existing tak folder ──────────────────────────────────────

tak_folder() {
    if [ -d "$PROJECT_DIR/tak" ]; then
        printf $warning "\nThe 'tak' directory already exists and will be removed to start fresh.\n"
        printf $warning "Continue? (y/n): "
        read -r dirc
        if [[ "$dirc" =~ ^[Nn] ]]; then
            printf "Exiting.\n"
            exit 0
        fi
        rm -rf "$PROJECT_DIR/tak"
        rm -rf /tmp/takserver
    fi
}

# ─── Checksum helpers (cross-platform) ───────────────────────────────────────

compute_sha1() {
    if command -v sha1sum &>/dev/null; then
        sha1sum "$1"
    elif command -v shasum &>/dev/null; then
        shasum -a 1 "$1"
    else
        printf $danger "ERROR: No SHA1 tool found (need sha1sum or shasum)\n"
        return 1
    fi
}

compute_md5() {
    if command -v md5sum &>/dev/null; then
        md5sum "$1"
    elif command -v md5 &>/dev/null; then
        md5 -r "$1"
    else
        printf $danger "ERROR: No MD5 tool found (need md5sum or md5)\n"
        return 1
    fi
}

# ─── Step 5: Verify checksums ────────────────────────────────────────────────

checksum() {
    printf $info "\n[Step 4/10] Verifying release checksums...\n"

    cd "$PROJECT_DIR" || exit 1

    local zip_files
    zip_files=$(ls -1 *-RELEASE-*.zip 2>/dev/null || true)

    if [ -z "$zip_files" ]; then
        printf $danger "\n  ERROR: No TAK release ZIP found in $PROJECT_DIR\n"
        printf $info "  Download from https://tak.gov/products/tak-server and place the ZIP here.\n"
        exit 1
    fi

    printf $warning "\n  SECURITY: Verify checksums match! Only use releases from tak.gov.\n\n"

    for file in *-RELEASE-*.zip; do
        printf "  File: $file\n"
        printf "  SHA1: $(compute_sha1 "$file" | awk '{print $1}')\n"
        printf "  MD5:  $(compute_md5 "$file" | awk '{print $1}')\n\n"
    done

    for file in *-RELEASE-*.zip; do
        local basename_file
        basename_file="$(basename "$file")"

        printf "  Verifying $basename_file against known checksums...\n"

        # SHA1 check
        local sha1_expected
        sha1_expected=$(grep "$basename_file" "$PROJECT_DIR/tak-sha1checksum.txt" 2>/dev/null | awk '{print $1}' || true)
        if [ -n "$sha1_expected" ]; then
            local sha1_computed
            sha1_computed=$(compute_sha1 "$file" | awk '{print $1}')
            if [ "$sha1_computed" = "$sha1_expected" ]; then
                printf $success "  SHA1: OK\n"
            else
                printf $danger "  SHA1: FAILED — checksum mismatch!\n"
                printf $danger "  Expected: $sha1_expected\n"
                printf $danger "  Got:      $sha1_computed\n"
                printf $danger "  Continue anyway? (y/n): "
                read -r check
                if [[ "$check" =~ ^[Nn] ]]; then
                    exit 1
                fi
            fi
        else
            printf $warning "  SHA1: Release not found in known checksums list.\n"
            printf $danger "  This release version is not in our checksum database. Continue? (y/n): "
            read -r check
            if [[ "$check" =~ ^[Nn] ]]; then
                exit 1
            fi
        fi

        # MD5 check
        local md5_expected
        md5_expected=$(grep "$basename_file" "$PROJECT_DIR/tak-md5checksum.txt" 2>/dev/null | awk '{print $1}' || true)
        if [ -n "$md5_expected" ]; then
            local md5_computed
            md5_computed=$(compute_md5 "$file" | awk '{print $1}')
            if [ "$md5_computed" = "$md5_expected" ]; then
                printf $success "  MD5:  OK\n"
            else
                printf $danger "  MD5:  FAILED — checksum mismatch!\n"
                printf $danger "  Expected: $md5_expected\n"
                printf $danger "  Got:      $md5_computed\n"
                printf $danger "  Continue anyway? (y/n): "
                read -r check
                if [[ "$check" =~ ^[Nn] ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

# ─── Step 6: Get network interface IP ────────────────────────────────────────

get_ip() {
    printf $info "\n[Step 5/10] Selecting network interface...\n"

    if [[ "$PLATFORM" == "darwin" ]]; then
        local interfaces
        interfaces=$(ifconfig -l | tr ' ' '\n' | grep -v '^lo')
        printf $warning "  Select the network interface your TAK clients will connect through:\n"
        select eth_interface in $interfaces; do
            if [ -n "$eth_interface" ]; then
                printf $success "  Selected: $eth_interface\n"
                break
            else
                printf $danger "  Invalid selection. Try again.\n"
            fi
        done
        IP=$(ifconfig "$eth_interface" | grep "inet " | awk '{print $2}')
    else
        local interfaces
        interfaces=$(ip link show | awk -F': ' '/^[0-9]/{print $2}' | grep -v '^lo')
        printf $warning "  Select the network interface your TAK clients will connect through:\n"
        select eth_interface in $interfaces; do
            if [ -n "$eth_interface" ]; then
                printf $success "  Selected: $eth_interface\n"
                break
            else
                printf $danger "  Invalid selection. Try again.\n"
            fi
        done
        IP=$(ip addr show "$eth_interface" | grep -m 1 "inet " | awk '{print $2}' | cut -d "/" -f1)
    fi

    if [ -z "$IP" ]; then
        printf $danger "\n  ERROR: Could not determine IP address for $eth_interface.\n"
        printf $info "  Check that the interface is up and has an IP assigned.\n"
        exit 1
    fi

    printf $success "  Using IP address: $IP\n"
}

# ─── Main Setup Flow ─────────────────────────────────────────────────────────

detect_platform
check_prerequisites
port_check
tak_folder

if [ -d "$PROJECT_DIR/tak" ]; then
    printf $danger "ERROR: Failed to remove the tak folder. You may need to run: sudo ./scripts/cleanup.sh\n"
    exit 1
fi

checksum

cd "$PROJECT_DIR" || exit 1

# ─── Determine release version ───────────────────────────────────────────────

release=$(ls -1 *-RELEASE-*.zip 2>/dev/null | head -1 | sed 's/\.zip$//' || true)

printf $warning "\nRelease: $release\n"
printf $warning "Starting setup in 5 seconds... Press Ctrl-C to cancel.\n"
sleep 5

# ─── Step 6: Extract release ─────────────────────────────────────────────────

printf $info "\n[Step 6/10] Extracting release...\n"

if [ -d "/tmp/takserver" ]; then
    rm -rf /tmp/takserver
fi

if command -v unzip &>/dev/null; then
    unzip -q "$release.zip" -d /tmp/takserver
elif command -v 7z &>/dev/null; then
    7z x "$release.zip" -o/tmp/takserver
fi

if [ ! -d "/tmp/takserver/$release/tak" ]; then
    printf $danger "\n  ERROR: Expected folder not found at /tmp/takserver/$release/tak\n"
    printf $danger "  The ZIP file structure may be different than expected. Check its contents.\n"
    exit 1
fi

mv -f "/tmp/takserver/$release/tak" "$PROJECT_DIR/"
if [[ "$PLATFORM" == "linux" ]]; then
    chown -R "$USER:$USER" "$PROJECT_DIR/tak"
fi

cp "$PROJECT_DIR/CoreConfig.xml" "$PROJECT_DIR/tak/CoreConfig.xml"
printf $success "  Release extracted and CoreConfig.xml copied.\n"

# ─── Generate passwords ──────────────────────────────────────────────────────

pwd=$(LC_ALL=C tr -dc '[:alpha:][:digit:]' < /dev/urandom | head -c 11 || true)
password="${pwd}Meh1!"

pgpwd=$(LC_ALL=C tr -dc '[:alpha:][:digit:]' < /dev/urandom | head -c 11 || true)
pgpassword="${pgpwd}Meh1!"

# ─── Network interface selection ──────────────────────────────────────────────

get_ip

# ─── Configure CoreConfig.xml ────────────────────────────────────────────────

printf $info "\n  Configuring CoreConfig.xml...\n"

if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s/password=\".*\"/password=\"${pgpassword}\"/" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i '' "s/HOSTIP/$IP/g" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i '' "s/takserver.jks/$IP.jks/g" "$PROJECT_DIR/tak/CoreConfig.xml"
else
    sed -i "s/password=\".*\"/password=\"${pgpassword}\"/" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i "s/HOSTIP/$IP/g" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i "s/takserver.jks/$IP.jks/g" "$PROJECT_DIR/tak/CoreConfig.xml"
fi

# ─── Memory allocation ───────────────────────────────────────────────────────

mem="4000000"
if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s%\`awk '/MemTotal/ {print \$2}' /proc/meminfo\`%$mem%g" "$PROJECT_DIR/tak/setenv.sh"
else
    sed -i "s%\`awk '/MemTotal/ {print \$2}' /proc/meminfo\`%$mem%g" "$PROJECT_DIR/tak/setenv.sh"
fi

# ─── Certificate defaults ────────────────────────────────────────────────────

country="US"
state="state"
city="city"
orgunit="TAK"
user="admin"

if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s/COUNTRY=US/COUNTRY=${country}/" "$PROJECT_DIR/tak/certs/cert-metadata.sh"
else
    sed -i "s/COUNTRY=US/COUNTRY=${country}/" "$PROJECT_DIR/tak/certs/cert-metadata.sh"
fi

# ─── Step 7: Build Docker images ─────────────────────────────────────────────

printf $info "\n[Step 7/10] Building Docker images ($DOCKER_ARCH)...\n"

printf $info "  Building tak-server-db...\n"
docker build -t tak-server-db:latest -f "$PROJECT_DIR/docker/$DOCKER_ARCH/Dockerfile.takserver-db" "$PROJECT_DIR"

printf $info "  Building tak-server...\n"
docker build -t tak-server:latest -f "$PROJECT_DIR/docker/$DOCKER_ARCH/Dockerfile.takserver" "$PROJECT_DIR"

printf $success "  Docker images built successfully.\n"

# ─── Step 8: Load images into Kubernetes ──────────────────────────────────────

printf $info "\n[Step 8/10] Loading images into Kubernetes...\n"

TAK_IMAGE="tak-server"
DB_IMAGE="tak-server-db"

if command -v k3s &>/dev/null || [ -f /etc/rancher/k3s/k3s.yaml ]; then
    printf $info "  k3s detected. Importing images into containerd...\n"

    docker save tak-server-db:latest -o /tmp/tak-server-db.tar
    docker save tak-server:latest -o /tmp/tak-server.tar

    printf $info "  Importing tak-server-db...\n"
    if ! sudo k3s ctr images import /tmp/tak-server-db.tar; then
        printf $danger "  ERROR: Failed to import tak-server-db into k3s containerd.\n"
        exit 1
    fi

    printf $info "  Importing tak-server...\n"
    if ! sudo k3s ctr images import /tmp/tak-server.tar; then
        printf $danger "  ERROR: Failed to import tak-server into k3s containerd.\n"
        exit 1
    fi

    rm -f /tmp/tak-server-db.tar /tmp/tak-server.tar

    printf $info "  Verifying images in k3s containerd...\n"
    local ctr_images
    ctr_images=$(sudo k3s ctr images list)
    echo "$ctr_images" | grep tak-server
    if ! echo "$ctr_images" | grep -q "tak-server-db"; then
        printf $danger "  ERROR: tak-server-db image not found in k3s containerd.\n"
        exit 1
    fi
    if ! echo "$ctr_images" | grep -q "tak-server:"; then
        printf $danger "  ERROR: tak-server image not found in k3s containerd.\n"
        exit 1
    fi
    printf $success "  Both images verified in k3s containerd.\n"

elif command -v minikube &>/dev/null && minikube status &>/dev/null; then
    printf $info "  Loading images into minikube...\n"
    minikube image load tak-server-db:latest
    minikube image load tak-server:latest

elif command -v kind &>/dev/null && kind get clusters &>/dev/null 2>&1; then
    printf $info "  Loading images into kind...\n"
    kind load docker-image tak-server-db:latest
    kind load docker-image tak-server:latest

else
    printf $warning "  No k3s, minikube, or kind detected.\n"
    printf $warning "  If using Docker Desktop Kubernetes, images should be available automatically.\n"
    printf $warning "  If images fail to pull, you may need to push them to a registry.\n"
fi

# ─── Create namespace ────────────────────────────────────────────────────────

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ─── Step 9: Deploy with Helm ────────────────────────────────────────────────

printf $info "\n[Step 9/10] Deploying TAK server to Kubernetes...\n"

# Deploy with replicas=0 first to create PVCs without starting pods
printf $info "  Creating PVCs (replicas=0)...\n"
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_DIR" \
    --namespace "$NAMESPACE" \
    --set takserver.image="$TAK_IMAGE" \
    --set takserver.tag=latest \
    --set takserver.pullPolicy=Never \
    --set takserver.replicas=0 \
    --set database.image="$DB_IMAGE" \
    --set database.tag=latest \
    --set database.pullPolicy=Never \
    --set database.replicas=0 \
    --set certs.country="$country" \
    --set certs.state="$state" \
    --set certs.city="$city" \
    --set certs.orgUnit="$orgunit"

printf $info "  Waiting for PVCs...\n"
sleep 3
kubectl get pvc -n "$NAMESPACE"

# Copy tak data into PVC via a temporary pod
printf $info "  Copying TAK data to persistent volume...\n"
kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: tak-data-init
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
    - name: init
      image: busybox:latest
      command: ["sh", "-c", "echo 'Data init pod ready' && sleep 3600"]
      volumeMounts:
        - name: tak-data
          mountPath: /mnt/tak-data
  volumes:
    - name: tak-data
      persistentVolumeClaim:
        claimName: ${RELEASE_NAME}-tak-server-tak-data
EOF

printf $info "  Waiting for data init pod...\n"
if ! kubectl wait --for=condition=Ready pod/tak-data-init -n "$NAMESPACE" --timeout=120s; then
    printf $danger "  ERROR: Data init pod failed to start. Check cluster storage.\n"
    kubectl describe pod/tak-data-init -n "$NAMESPACE"
    exit 1
fi

kubectl cp "$PROJECT_DIR/tak/" "$NAMESPACE/tak-data-init:/mnt/tak-data/"
kubectl exec -n "$NAMESPACE" tak-data-init -- sh -c "cp -a /mnt/tak-data/tak/* /mnt/tak-data/ && rm -rf /mnt/tak-data/tak"
kubectl delete pod tak-data-init -n "$NAMESPACE" --wait=true
printf $success "  TAK data copied to persistent volume.\n"

# Scale up to replicas=1
printf $info "  Starting TAK server pods...\n"
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_DIR" \
    --namespace "$NAMESPACE" \
    --set takserver.image="$TAK_IMAGE" \
    --set takserver.tag=latest \
    --set takserver.pullPolicy=Never \
    --set takserver.replicas=1 \
    --set database.image="$DB_IMAGE" \
    --set database.tag=latest \
    --set database.pullPolicy=Never \
    --set database.replicas=1 \
    --set certs.country="$country" \
    --set certs.state="$state" \
    --set certs.city="$city" \
    --set certs.orgUnit="$orgunit"

# Wait for pods
printf $info "  Waiting for database to be ready...\n"
if ! kubectl rollout status deployment/"${RELEASE_NAME}-tak-server-db" -n "$NAMESPACE" --timeout=600s; then
    printf $danger "  ERROR: Database deployment failed to become ready.\n"
    printf $info "  Debug: kubectl logs -f deployment/${RELEASE_NAME}-tak-server-db -n $NAMESPACE\n"
    exit 1
fi

printf $info "  Waiting for TAK server container to start...\n"
if ! kubectl rollout status deployment/"${RELEASE_NAME}-tak-server-tak" -n "$NAMESPACE" --timeout=600s; then
    printf $danger "  ERROR: TAK server deployment failed to start.\n"
    printf $info "  Debug: kubectl logs -f deployment/${RELEASE_NAME}-tak-server-tak -n $NAMESPACE\n"
    exit 1
fi

TAK_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=takserver" -o jsonpath='{.items[0].metadata.name}')
DB_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=database" -o jsonpath='{.items[0].metadata.name}')

# Wait for the TAK container to be running (not just scheduled)
printf $info "  Waiting for TAK server process to initialize...\n"
sleep 15

# Wait for database schema initialization
printf $info "  Waiting for database schema initialization (martiuser role)...\n"
DB_INIT_RETRIES=0
DB_INIT_MAX=60
while [ $DB_INIT_RETRIES -lt $DB_INIT_MAX ]; do
    DB_INIT_RETRIES=$((DB_INIT_RETRIES + 1))
    MARTIUSER_EXISTS=$(kubectl exec -n "$NAMESPACE" "$DB_POD" -- su - postgres -c "psql -AXqtc \"SELECT 1 FROM pg_roles WHERE rolname='martiuser'\"" 2>/dev/null || true)
    if [ "$MARTIUSER_EXISTS" = "1" ]; then
        printf $success "  Database schema ready (martiuser role exists).\n"
        if kubectl exec -n "$NAMESPACE" "$DB_POD" -- su - postgres -c "psql -c \"ALTER USER martiuser WITH PASSWORD '${pgpassword}';\"" &>/dev/null; then
            printf $success "  Database password synchronized with CoreConfig.xml.\n"
        fi
        break
    fi
    if [ $((DB_INIT_RETRIES % 6)) -eq 0 ]; then
        printf $info "  Still waiting for martiuser role (attempt $DB_INIT_RETRIES/$DB_INIT_MAX)...\n"
    fi
    sleep 5
done

if [ "$MARTIUSER_EXISTS" != "1" ]; then
    printf $danger "\n  ERROR: Database schema failed to initialize after $DB_INIT_MAX attempts.\n"
    printf $info "  Debug: kubectl logs -f -n $NAMESPACE $DB_POD\n"
    exit 1
fi

# ─── Step 10: Generate certificates ──────────────────────────────────────────
#
# The TAK server is starting up via configureInDocker.sh. We generate certs
# while it's still initializing — by the time the Java process tries to load
# its keystore, our cert files will already be on disk. This matches the
# original docker-compose setup flow (no restart needed).

printf $info "\n[Step 10/10] Generating certificates...\n"

# Don't wipe certs — configureInDocker.sh needs its files during startup.
# makeRootCa.sh will overwrite the CA and truststore with ours.

CERT_RETRIES=0
CERT_MAX_RETRIES=20
while :; do
    sleep 5
    CERT_RETRIES=$((CERT_RETRIES + 1))
    if [ $CERT_RETRIES -gt $CERT_MAX_RETRIES ]; then
        printf $danger "  ERROR: Certificate generation failed after $CERT_MAX_RETRIES attempts.\n"
        printf $info "  Debug: kubectl exec -n $NAMESPACE $TAK_POD -- ls -la /opt/tak/certs/\n"
        exit 1
    fi

    printf $info "  Generating Root CA...\n"
    if kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeRootCa.sh --ca-name takserver" 2>&1; then
        printf $info "  Generating server certificate ($IP)...\n"
        if kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh server $IP" 2>&1; then
            printf $info "  Generating admin client certificate...\n"
            if kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client $user" 2>&1; then
                kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "chown -R 1000:1000 /opt/tak/certs/"
                break
            fi
        fi
    fi

    printf $warning "  Certificate generation not ready (attempt $CERT_RETRIES/$CERT_MAX_RETRIES), retrying...\n"
done

printf $info "  Generating additional user certificates (user1, user2)...\n"
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client user1"
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client user2"
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "chown -R 1000:1000 /opt/tak/certs/"

# Copy certs locally for data package creation
mkdir -p "$PROJECT_DIR/tak/certs/files"
kubectl cp "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/" "$PROJECT_DIR/tak/certs/files/"

printf $info "  Building data packages...\n"
"$PROJECT_DIR/scripts/certDP.sh" "$IP" user1
"$PROJECT_DIR/scripts/certDP.sh" "$IP" user2

# Copy data packages back into the PVC
kubectl cp "$PROJECT_DIR/tak/certs/files/" "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/"

# ─── Set up admin user ───────────────────────────────────────────────────────
#
# UserManager.jar connects to the TAK server via Ignite services. The TAK
# server must be fully initialized before this will work, so we retry until
# the Ignite service (distributed-user-file-manager) is registered.

printf $info "\n  Creating admin user and running schema upgrade...\n"
printf $info "  Waiting for TAK server Ignite services to be ready (this may take a few minutes)...\n"

RETRY_COUNT=0
MAX_RETRIES=30
while :; do
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
        printf $danger "\n  ERROR: Admin setup failed after $MAX_RETRIES attempts.\n"
        printf $info "  Debug commands:\n"
        printf $info "    kubectl logs -f deployment/${RELEASE_NAME}-tak-server-tak -n $NAMESPACE\n"
        printf $info "    kubectl logs -f deployment/${RELEASE_NAME}-tak-server-db -n $NAMESPACE\n"
        exit 1
    fi

    if kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/ && java -jar /opt/tak/utils/UserManager.jar usermod -A -p '$password' $user" 2>&1; then
        if kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/ && java -jar utils/UserManager.jar certmod -A certs/files/$user.pem" 2>&1; then
            if kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "java -jar /opt/tak/db-utils/SchemaManager.jar upgrade" 2>&1; then
                printf $success "  Admin user created and schema upgraded.\n"
                break
            fi
        fi
    fi

    printf $info "  Not ready yet (attempt $RETRY_COUNT/$MAX_RETRIES), retrying...\n"
done

# Register user1 and user2
printf $info "  Registering user1 and user2...\n"
u1pwd=$(LC_ALL=C tr -dc '[:alpha:][:digit:]' < /dev/urandom | head -c 11 || true)
u2pwd=$(LC_ALL=C tr -dc '[:alpha:][:digit:]' < /dev/urandom | head -c 11 || true)
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak && java -jar utils/UserManager.jar usermod -p '${u1pwd}Meh1!' user1" 2>&1 || true
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak && java -jar utils/UserManager.jar certmod certs/files/user1.pem" 2>&1 || true
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak && java -jar utils/UserManager.jar usermod -p '${u2pwd}Meh1!' user2" 2>&1 || true
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak && java -jar utils/UserManager.jar certmod certs/files/user2.pem" 2>&1 || true

# Copy admin cert locally
kubectl cp "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/$user.p12" "$PROJECT_DIR/$user.p12"

# ─── Summary ─────────────────────────────────────────────────────────────────

printf "\n"
kubectl get pods -n "$NAMESPACE"

NODE_PORT=$(kubectl get svc "${RELEASE_NAME}-tak-server-tak" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || true)

printf $success "\n========================================\n"
printf $success "  TAK Server Setup Complete\n"
printf $success "========================================\n\n"

printf $warning "Import $user.p12 to your browser's certificate store (password: atakatak)\n\n"

if [ -n "$NODE_PORT" ]; then
    printf $success "Web UI: https://$IP:$NODE_PORT\n"
else
    printf $success "Web UI: https://$IP:8443\n"
    printf $info "You may need port-forwarding:\n"
    printf $info "  kubectl port-forward svc/${RELEASE_NAME}-tak-server-tak 8443:8443 -n $NAMESPACE\n"
fi

printf $info "\nCertificates and data packages: tak/certs/files/\n"

printf $danger "\n---------CREDENTIALS---------\n\n"
printf $danger "Admin username:     $user\n"
printf $danger "Admin password:     $password\n"
printf $danger "PostgreSQL password: $pgpassword\n\n"
printf $danger "-----------------------------\n\n"
printf $warning "SAVE THESE CREDENTIALS NOW. They will not be shown again.\n\n"

printf $info "Namespace: $NAMESPACE | Helm release: $RELEASE_NAME\n"
printf $info "\n---------USEFUL COMMANDS---------\n\n"
printf $info "Port-forward (access UI at https://localhost:8443):\n"
printf $info "  kubectl port-forward svc/${RELEASE_NAME}-tak-server-tak 8443:8443 8089:8089 -n $NAMESPACE\n\n"
printf $info "Check pod status:\n"
printf $info "  kubectl get pods -n $NAMESPACE\n\n"
printf $info "View logs:\n"
printf $info "  kubectl logs -f deployment/${RELEASE_NAME}-tak-server-tak -n $NAMESPACE\n\n"
printf $info "Shell into TAK server:\n"
printf $info "  kubectl exec -it -n $NAMESPACE deployment/${RELEASE_NAME}-tak-server-tak -- bash\n\n"
printf $info "Clean up everything:\n"
printf $info "  ./scripts/cleanup.sh\n"
