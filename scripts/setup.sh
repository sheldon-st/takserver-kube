#!/bin/bash

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

NAMESPACE="tak"
RELEASE_NAME="tak-server"
HELM_CHART_DIR="$(cd "$(dirname "$0")/../helm/tak-server" && pwd)"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

printf $success "\nTAK server setup script (Kubernetes/Helm) sponsored by CloudRF.com - \"The API for RF\"\n"
printf $info "\nStep 1. Download the official docker image as a zip file from https://tak.gov/products/tak-server \nStep 2. Place the zip file in the tak-server folder.\n"
printf $warning "\nThis script requires: kubectl, helm, and docker (for building images)\n"

### Detect OS and architecture
detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)  PLATFORM="linux" ;;
        Darwin) PLATFORM="darwin" ;;
        *)      printf $danger "\nUnsupported OS: $OS\n"; exit 1 ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  DOCKER_ARCH="amd64" ;;
        arm64|aarch64) DOCKER_ARCH="arm64" ;;
        *)             printf $danger "\nUnsupported architecture: $ARCH\n"; exit 1 ;;
    esac

    printf $info "\nDetected platform: $PLATFORM/$DOCKER_ARCH\n"
}

### Check required tools
check_prerequisites() {
    local missing=0
    for cmd in kubectl helm docker; do
        if ! command -v $cmd &>/dev/null; then
            printf $danger "\nRequired tool '$cmd' is not installed.\n"
            missing=1
        fi
    done

    if ! command -v unzip &>/dev/null && ! command -v 7z &>/dev/null; then
        printf $danger "\nRequired tool 'unzip' or '7z' is not installed.\n"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        printf $danger "\nPlease install missing tools and try again.\n"
        exit 1
    fi

    # Check kubectl can connect to a cluster
    if ! kubectl cluster-info &>/dev/null; then
        printf $danger "\nCannot connect to a Kubernetes cluster. Ensure kubectl is configured.\n"
        printf $info "For local development, install minikube, kind, or Docker Desktop with Kubernetes enabled.\n"
        exit 1
    fi

    printf $success "\nAll prerequisites met. Connected to Kubernetes cluster.\n"
}

### Check if required ports are available
port_check() {
    local ports=(8089 8443 8444 8446 9000 9001)
    for port in "${ports[@]}"; do
        if command -v lsof &>/dev/null; then
            if lsof -i :"$port" &>/dev/null; then
                printf $warning "\nPort $port is in use. This may cause conflicts with NodePort services.\n"
            else
                printf $success "\nPort $port is available.."
            fi
        elif command -v ss &>/dev/null; then
            if ss -ltn | grep -q ":${port} " 2>/dev/null; then
                printf $warning "\nPort $port is in use. This may cause conflicts with NodePort services.\n"
            else
                printf $success "\nPort $port is available.."
            fi
        fi
    done
}

### Handle existing tak folder
tak_folder() {
    if [ -d "$PROJECT_DIR/tak" ]; then
        printf $warning "\nDirectory 'tak' already exists. This will be removed. Continue? (y/n): "
        read -r dirc
        if [[ "$dirc" =~ ^[Nn] ]]; then
            printf "Exiting now..\n"
            exit 0
        fi
        rm -rf "$PROJECT_DIR/tak"
        rm -rf /tmp/takserver
    fi
}

### Checksum verification (cross-platform)
compute_sha1() {
    if command -v sha1sum &>/dev/null; then
        sha1sum "$1"
    elif command -v shasum &>/dev/null; then
        shasum -a 1 "$1"
    else
        printf $danger "\nNo SHA1 tool found (need sha1sum or shasum)\n"
        return 1
    fi
}

compute_md5() {
    if command -v md5sum &>/dev/null; then
        md5sum "$1"
    elif command -v md5 &>/dev/null; then
        # macOS md5 outputs differently, reformat to match md5sum style
        md5 -r "$1"
    else
        printf $danger "\nNo MD5 tool found (need md5sum or md5)\n"
        return 1
    fi
}

checksum() {
    printf "\nChecking for TAK server release files (..RELEASE.zip) in the directory....\n"

    cd "$PROJECT_DIR" || exit 1

    local zip_files
    zip_files=$(ls -1 *-RELEASE-*.zip 2>/dev/null)

    if [ -z "$zip_files" ]; then
        printf $danger "\n\tPlease download the release of docker image as per instructions in README.md file. Exiting now...\n\n"
        exit 0
    fi

    printf $warning "SECURITY WARNING: Make sure the checksums match! You should only download your release from a trusted source eg. tak.gov:\n"
    for file in *-RELEASE-*.zip; do
        printf "Computed SHA1 Checksum: "
        compute_sha1 "$file"
        printf "Computed MD5 Checksum: "
        compute_md5 "$file"
    done

    # Verify against known checksums
    local file
    for file in *-RELEASE-*.zip; do
        local basename_file
        basename_file="$(basename "$file")"

        printf "\nVerifying checksums against known values for $basename_file...\n"

        # SHA1 check
        local sha1_expected
        sha1_expected=$(grep "$basename_file" "$PROJECT_DIR/tak-sha1checksum.txt" 2>/dev/null | awk '{print $1}')
        if [ -n "$sha1_expected" ]; then
            local sha1_computed
            sha1_computed=$(compute_sha1 "$file" | awk '{print $1}')
            if [ "$sha1_computed" = "$sha1_expected" ]; then
                printf $success "SHA1 Verification: OK\n"
            else
                printf $danger "SHA1 Verification: FAILED\n"
                printf $danger "SECURITY WARNING: Checksum mismatch. Continue? (y/n): "
                read -r check
                if [[ "$check" =~ ^[Nn] ]]; then
                    printf "\nExiting now..."
                    exit 0
                fi
            fi
        else
            printf $warning "SHA1: Release not found in known checksums list.\n"
            printf $danger "Do you want to continue with this setup? (y/n): "
            read -r check
            if [[ "$check" =~ ^[Nn] ]]; then
                printf "\nExiting now..."
                exit 0
            fi
        fi

        # MD5 check
        local md5_expected
        md5_expected=$(grep "$basename_file" "$PROJECT_DIR/tak-md5checksum.txt" 2>/dev/null | awk '{print $1}')
        if [ -n "$md5_expected" ]; then
            local md5_computed
            md5_computed=$(compute_md5 "$file" | awk '{print $1}')
            if [ "$md5_computed" = "$md5_expected" ]; then
                printf $success "MD5 Verification: OK\n"
            else
                printf $danger "MD5 Verification: FAILED\n"
                printf $danger "SECURITY WARNING: Checksum mismatch. Continue? (y/n): "
                read -r check
                if [[ "$check" =~ ^[Nn] ]]; then
                    printf "\nExiting now..."
                    exit 0
                fi
            fi
        fi
    done
}

### Get network interface IP (cross-platform)
get_ip() {
    if [[ "$PLATFORM" == "darwin" ]]; then
        # macOS: list active network interfaces
        local interfaces
        interfaces=$(ifconfig -l | tr ' ' '\n' | grep -v '^lo')
        printf $danger "Choose your TAK SERVER network interface wisely...\n"
        select eth_interface in $interfaces; do
            if [ -n "$eth_interface" ]; then
                printf $success "You chose $eth_interface\n"
                break
            else
                printf $danger "Invalid selection. Choose again.\n"
            fi
        done
        IP=$(ifconfig "$eth_interface" | grep "inet " | awk '{print $2}')
    else
        # Linux
        local interfaces
        interfaces=$(ip link show | awk -F': ' '/^[0-9]/{print $2}' | grep -v '^lo')
        printf $danger "Choose your TAK SERVER network interface wisely...\n"
        select eth_interface in $interfaces; do
            if [ -n "$eth_interface" ]; then
                printf $success "You chose $eth_interface\n"
                break
            else
                printf $danger "Invalid selection. Choose again.\n"
            fi
        done
        IP=$(ip addr show "$eth_interface" | grep -m 1 "inet " | awk '{print $2}' | cut -d "/" -f1)
    fi

    if [ -z "$IP" ]; then
        printf $danger "\nCould not determine IP address for $eth_interface\n"
        exit 1
    fi

    printf $info "\nProceeding with IP address: $IP\n"
}

### Main setup flow

detect_platform
check_prerequisites
port_check
tak_folder

if [ -d "$PROJECT_DIR/tak" ]; then
    printf $danger "Failed to remove the tak folder. You may need to run: sudo ./scripts/cleanup.sh\n"
    exit 0
fi

checksum

cd "$PROJECT_DIR" || exit 1

### Determine release
release=$(ls -1 *-RELEASE-*.zip 2>/dev/null | head -1 | sed 's/\.zip$//')

printf $warning "\nPausing to let you know release version $release will be setup in 5 seconds.\nIf this is wrong, hit Ctrl-C now..."
sleep 5

### Extract release
if [ -d "/tmp/takserver" ]; then
    rm -rf /tmp/takserver
fi

if command -v unzip &>/dev/null; then
    unzip "$release.zip" -d /tmp/takserver
elif command -v 7z &>/dev/null; then
    7z x "$release.zip" -o/tmp/takserver
fi

if [ ! -d "/tmp/takserver/$release/tak" ]; then
    printf $danger "\nA decompressed folder was NOT found at /tmp/takserver/$release\n"
    printf $danger "Check the zip file structure. Exiting.\n"
    exit 1
fi

mv -f "/tmp/takserver/$release/tak" "$PROJECT_DIR/"
if [[ "$PLATFORM" == "linux" ]]; then
    chown -R "$USER:$USER" "$PROJECT_DIR/tak"
fi

# Copy CoreConfig template
cp "$PROJECT_DIR/CoreConfig.xml" "$PROJECT_DIR/tak/CoreConfig.xml"

## Generate passwords
pwd=$(cat /dev/urandom | LC_ALL=C tr -dc '[:alpha:][:digit:]' | fold -w 11 | head -n 1)
password="${pwd}Meh1!"

pgpwd=$(cat /dev/urandom | LC_ALL=C tr -dc '[:alpha:][:digit:]' | fold -w 11 | head -n 1)
pgpassword="${pgpwd}Meh1!"

## Get network IP
get_ip

## Configure CoreConfig.xml using cross-platform sed
if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s/password=\".*\"/password=\"${pgpassword}\"/" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i '' "s/HOSTIP/$IP/g" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i '' "s/takserver.jks/$IP.jks/g" "$PROJECT_DIR/tak/CoreConfig.xml"
else
    sed -i "s/password=\".*\"/password=\"${pgpassword}\"/" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i "s/HOSTIP/$IP/g" "$PROJECT_DIR/tak/CoreConfig.xml"
    sed -i "s/takserver.jks/$IP.jks/g" "$PROJECT_DIR/tak/CoreConfig.xml"
fi

## Memory allocation
mem="4000000"
if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s%\`awk '/MemTotal/ {print \$2}' /proc/meminfo\`%$mem%g" "$PROJECT_DIR/tak/setenv.sh"
else
    sed -i "s%\`awk '/MemTotal/ {print \$2}' /proc/meminfo\`%$mem%g" "$PROJECT_DIR/tak/setenv.sh"
fi

## Certificate defaults
country="US"
state="state"
city="city"
orgunit="TAK"

## Update cert-metadata.sh
if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s/COUNTRY=US/COUNTRY=${country}/" "$PROJECT_DIR/tak/certs/cert-metadata.sh"
else
    sed -i "s/COUNTRY=US/COUNTRY=${country}/" "$PROJECT_DIR/tak/certs/cert-metadata.sh"
fi

user="admin"

### Build Docker images
printf $info "\nBuilding Docker images for $DOCKER_ARCH...\n"

docker build -t tak-server-db:latest -f "$PROJECT_DIR/docker/$DOCKER_ARCH/Dockerfile.takserver-db" "$PROJECT_DIR"
docker build -t tak-server:latest -f "$PROJECT_DIR/docker/$DOCKER_ARCH/Dockerfile.takserver" "$PROJECT_DIR"

### Load images into Kubernetes cluster
if command -v k3s &>/dev/null || [ -f /etc/rancher/k3s/k3s.yaml ]; then
    printf $info "\nk3s detected. Loading Docker images into k3s containerd...\n"
    docker save tak-server-db:latest | sudo k3s ctr images import -
    docker save tak-server:latest | sudo k3s ctr images import -
elif command -v minikube &>/dev/null && minikube status &>/dev/null; then
    printf $info "\nLoading Docker images into minikube...\n"
    minikube image load tak-server-db:latest
    minikube image load tak-server:latest
elif command -v kind &>/dev/null && kind get clusters &>/dev/null 2>&1; then
    printf $info "\nLoading Docker images into kind...\n"
    kind load docker-image tak-server-db:latest
    kind load docker-image tak-server:latest
else
    printf $warning "\nNo k3s, minikube, or kind detected. If using Docker Desktop Kubernetes, images should be available automatically.\n"
    printf $warning "If images fail to pull, you may need to push them to a registry or load them manually.\n"
fi

### Create Kubernetes namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

### Deploy with Helm
printf $info "\nDeploying TAK server to Kubernetes with Helm...\n"

# Deploy with replicas=0 first so PVCs are created but pods don't start yet
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_DIR" \
    --namespace "$NAMESPACE" \
    --set takserver.image=tak-server \
    --set takserver.tag=latest \
    --set takserver.pullPolicy=Never \
    --set takserver.replicas=0 \
    --set database.image=tak-server-db \
    --set database.tag=latest \
    --set database.pullPolicy=Never \
    --set database.replicas=0 \
    --set certs.country="$country" \
    --set certs.state="$state" \
    --set certs.city="$city" \
    --set certs.orgUnit="$orgunit"

# Wait for PVC to be created
printf $info "\nWaiting for PVCs to be ready...\n"
sleep 3
kubectl get pvc -n "$NAMESPACE"

# Copy tak data into PVC via a temporary pod
printf $info "\nCopying TAK data to persistent volume...\n"
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

printf $info "\nWaiting for data init pod to be ready...\n"
kubectl wait --for=condition=Ready pod/tak-data-init -n "$NAMESPACE" --timeout=120s

# Copy the tak directory contents into the PVC
# kubectl cp copies the directory itself, so we copy into /mnt/tak-data/
# The PVC is mounted at /mnt/tak-data, and deployments mount it at /opt/tak
# So contents end up at PVC root when accessed from /opt/tak
kubectl cp "$PROJECT_DIR/tak/" "$NAMESPACE/tak-data-init:/mnt/tak-data/"
# Move contents up: /mnt/tak-data/tak/* -> /mnt/tak-data/*
kubectl exec -n "$NAMESPACE" tak-data-init -- sh -c "cp -a /mnt/tak-data/tak/* /mnt/tak-data/ && rm -rf /mnt/tak-data/tak"

# Clean up init pod
kubectl delete pod tak-data-init -n "$NAMESPACE" --wait=true

# Now scale up deployments with replicas=1
printf $info "\nStarting TAK server pods...\n"
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_DIR" \
    --namespace "$NAMESPACE" \
    --set takserver.image=tak-server \
    --set takserver.tag=latest \
    --set takserver.pullPolicy=Never \
    --set takserver.replicas=1 \
    --set database.image=tak-server-db \
    --set database.tag=latest \
    --set database.pullPolicy=Never \
    --set database.replicas=1 \
    --set certs.country="$country" \
    --set certs.state="$state" \
    --set certs.city="$city" \
    --set certs.orgUnit="$orgunit"

### Wait for TAK server to be ready
printf $info "\nWaiting for TAK server pods to be ready...\n"
kubectl rollout status deployment/"${RELEASE_NAME}-tak-server-db" -n "$NAMESPACE" --timeout=300s
kubectl rollout status deployment/"${RELEASE_NAME}-tak-server-tak" -n "$NAMESPACE" --timeout=300s

TAK_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=takserver" -o jsonpath='{.items[0].metadata.name}')
DB_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=database" -o jsonpath='{.items[0].metadata.name}')

### Wait for database to fully initialize (configureInDocker.sh creates martiuser)
printf $info "\nWaiting for database initialization to complete...\n"
printf $info "The DB entrypoint script needs time to initialize PostgreSQL and create the martiuser role.\n"
DB_INIT_RETRIES=0
DB_INIT_MAX=60
while [ $DB_INIT_RETRIES -lt $DB_INIT_MAX ]; do
    DB_INIT_RETRIES=$((DB_INIT_RETRIES + 1))
    # Check if martiuser role exists
    MARTIUSER_EXISTS=$(kubectl exec -n "$NAMESPACE" "$DB_POD" -- su - postgres -c "psql -AXqtc \"SELECT 1 FROM pg_roles WHERE rolname='martiuser'\"" 2>/dev/null)
    if [ "$MARTIUSER_EXISTS" = "1" ]; then
        printf $success "\nDatabase initialized - martiuser role exists.\n"
        # Now sync the password to guarantee it matches CoreConfig.xml
        kubectl exec -n "$NAMESPACE" "$DB_POD" -- su - postgres -c "psql -c \"ALTER USER martiuser WITH PASSWORD '${pgpassword}';\""
        if [ $? -eq 0 ]; then
            printf $success "Database password synchronized.\n"
        fi
        break
    fi
    if [ $((DB_INIT_RETRIES % 6)) -eq 0 ]; then
        printf $info "Still waiting for DB init (attempt $DB_INIT_RETRIES/$DB_INIT_MAX)... checking DB logs:\n"
        kubectl logs --tail=5 -n "$NAMESPACE" "$DB_POD" 2>/dev/null
    fi
    sleep 5
done

if [ "$MARTIUSER_EXISTS" != "1" ]; then
    printf $danger "\nDatabase failed to initialize after $DB_INIT_MAX attempts.\n"
    printf $info "Check DB logs: kubectl logs -f -n $NAMESPACE $DB_POD\n"
    exit 1
fi

### Generate certificates
# Clean up any existing certs from a previous run
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "rm -f /opt/tak/certs/files/ca.pem /opt/tak/certs/files/ca-trusted.pem /opt/tak/certs/files/ca.key /opt/tak/certs/files/root-ca.pem /opt/tak/certs/files/root-ca-trusted.pem /opt/tak/certs/files/root-ca.key" 2>/dev/null

while :; do
    sleep 5
    printf $warning "------------CERTIFICATE GENERATION--------------\n"
    kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeRootCa.sh --ca-name CRFtakserver"
    if [ $? -eq 0 ]; then
        kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh server $IP"
        if [ $? -eq 0 ]; then
            kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client $user"
            if [ $? -eq 0 ]; then
                kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "chown -R 1000:1000 /opt/tak/certs/"
                break
            fi
        else
            sleep 5
        fi
    fi
done

printf $info "Creating certificates for 2 users in tak/certs/files for a quick setup via TAK's import function\n"

kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client user1"
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/certs && ./makeCert.sh client user2"
kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "chown -R 1000:1000 /opt/tak/certs/"

# Copy certs back from PVC for local data package creation
mkdir -p "$PROJECT_DIR/tak/certs/files"
kubectl cp "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/" "$PROJECT_DIR/tak/certs/files/"

"$PROJECT_DIR/scripts/certDP.sh" "$IP" user1
"$PROJECT_DIR/scripts/certDP.sh" "$IP" user2

# Copy data packages back into the PVC
kubectl cp "$PROJECT_DIR/tak/certs/files/" "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/"

printf $info "Waiting for TAK server services to initialize (this can take 1-2 minutes)...\n"
sleep 30

### Set up admin user and database
RETRY_COUNT=0
MAX_RETRIES=30
while :; do
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
        printf $danger "\nFailed after $MAX_RETRIES attempts. Check TAK server logs:\n"
        printf $info "  kubectl logs -f deployment/${RELEASE_NAME}-tak-server-tak -n $NAMESPACE\n"
        printf $info "  kubectl logs -f deployment/${RELEASE_NAME}-tak-server-db -n $NAMESPACE\n"
        exit 1
    fi
    kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/ && java -jar /opt/tak/utils/UserManager.jar usermod -A -p '$password' $user"
    if [ $? -eq 0 ]; then
        kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "cd /opt/tak/ && java -jar utils/UserManager.jar certmod -A certs/files/$user.pem"
        if [ $? -eq 0 ]; then
            kubectl exec -n "$NAMESPACE" "$TAK_POD" -- bash -c "java -jar /opt/tak/db-utils/SchemaManager.jar upgrade"
            if [ $? -eq 0 ]; then
                break
            else
                sleep 10
            fi
        else
            sleep 10
        fi
    else
        printf $info "TAK server not ready yet (attempt $RETRY_COUNT/$MAX_RETRIES), retrying in 10s...\n"
    fi
done

# Copy admin cert locally
kubectl cp "$NAMESPACE/$TAK_POD:/opt/tak/certs/files/$user.p12" "$PROJECT_DIR/$user.p12"

### Post-installation summary
printf "\n"
kubectl get pods -n "$NAMESPACE"

printf $warning "\n\nImport the $user.p12 certificate from this folder to your browser's certificate store as per the README.md file\n"

# Determine access URL
NODE_PORT=$(kubectl get svc "${RELEASE_NAME}-tak-server-tak" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null)
if [ -n "$NODE_PORT" ]; then
    printf $success "Login at https://$IP:$NODE_PORT with your admin account. No need to run the /setup step as this has been done.\n"
else
    printf $success "Login at https://$IP:8443 with your admin account. No need to run the /setup step as this has been done.\n"
    printf $info "You may need to set up port-forwarding: kubectl port-forward svc/${RELEASE_NAME}-tak-server-tak 8443:8443 -n $NAMESPACE\n"
fi

printf $info "Certificates and .zip data packages are in tak/certs/files \n\n"
printf $success "Setup script sponsored by CloudRF.com - \"The API for RF\"\n\n"
printf $danger "---------PASSWORDS----------------\n\n"
printf $danger "Admin user name: $user\n"
printf $danger "Admin password: $password\n"
printf $danger "PostgreSQL password: $pgpassword\n\n"
printf $danger "---------PASSWORDS----------------\n\n"
printf $warning "MAKE A NOTE OF YOUR PASSWORDS. THEY WON'T BE SHOWN AGAIN.\n"
printf $info "Kubernetes namespace: $NAMESPACE\n"
printf $info "Helm release: $RELEASE_NAME\n"
printf $info "\n---------USEFUL COMMANDS----------\n\n"
printf $info "Port-forward (access UI at https://localhost:8443):\n"
printf $info "  kubectl port-forward svc/${RELEASE_NAME}-tak-server-tak 8443:8443 8089:8089 -n $NAMESPACE\n\n"
printf $info "Check pod status:\n"
printf $info "  kubectl get pods -n $NAMESPACE\n\n"
printf $info "View logs:\n"
printf $info "  kubectl logs -f deployment/${RELEASE_NAME}-tak-server-tak -n $NAMESPACE\n\n"
printf $info "Shell into TAK server:\n"
printf $info "  kubectl exec -it -n $NAMESPACE deployment/${RELEASE_NAME}-tak-server-tak -- bash\n\n"
printf $info "Clean up everything:\n"
printf $info "  sudo ./scripts/cleanup.sh\n"
