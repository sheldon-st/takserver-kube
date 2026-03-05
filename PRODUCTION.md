# Production Deployment Guide

This guide covers deploying TAK Server on a VPS with Kubernetes, a reverse proxy, TLS termination, and subdomain routing.

## Table of Contents

- [VPS Requirements](#vps-requirements)
- [VPS Setup](#vps-setup)
- [Install Kubernetes (k3s)](#install-kubernetes-k3s)
- [Install TAK Server](#install-tak-server)
- [Reverse Proxy with Nginx](#reverse-proxy-with-nginx)
- [Subdomain Setup](#subdomain-setup)
- [Firewall Configuration](#firewall-configuration)
- [Architecture Overview](#architecture-overview)
- [Backups](#backups)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

---

## VPS Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU      | 2 cores | 4 cores     |
| RAM      | 4 GB    | 8 GB        |
| Disk     | 40 GB   | 80 GB SSD   |
| OS       | Ubuntu 22.04+ or Debian 12+ | Ubuntu 24.04 LTS |

Tested providers: Hetzner, DigitalOcean, Linode, Vultr, AWS EC2, OVH.

## VPS Setup

SSH into your VPS and run initial setup:

```bash
# Update system
sudo apt update && sudo apt upgrade -y
sudo apt install -y unzip zip curl git

# Set hostname
sudo hostnamectl set-hostname tak-server

# Create a non-root user (if not already)
sudo adduser tak
sudo usermod -aG sudo tak
```

### Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for group to take effect
```

## Install Kubernetes (k3s)

For a single-node VPS, [k3s](https://k3s.io/) is the best choice -- lightweight, production-ready, and includes everything needed.

```bash
# Install k3s (includes kubectl, no separate install needed)
curl -sfL https://get.k3s.io | sh -

# Verify
sudo kubectl get nodes

# Make kubectl work without sudo
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
```

### Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Why k3s over minikube/kind?

- k3s is production-grade, minikube/kind are for development
- k3s includes a built-in Ingress controller (Traefik)
- k3s includes a built-in LoadBalancer (ServiceLB)
- k3s uses fewer resources
- k3s auto-starts on boot

## Install TAK Server

```bash
git clone https://github.com/Cloud-RF/tak-server.git
cd tak-server

# Copy your TAK release ZIP here
# e.g., scp takserver-docker-5.5-RELEASE-58.zip user@vps:~/tak-server/

chmod +x scripts/setup.sh
./scripts/setup.sh
```

The setup script will:
1. Build Docker images
2. Load them into the k3s containerd runtime
3. Deploy via Helm into the `tak` namespace
4. Generate certificates and admin credentials

> **Note:** On k3s, Docker images need to be imported into k3s's containerd. If the setup script doesn't detect k3s automatically, you can manually import:
> ```bash
> docker save tak-server:latest | sudo k3s ctr images import -
> docker save tak-server-db:latest | sudo k3s ctr images import -
> ```

After setup completes, verify pods are running:

```bash
kubectl get pods -n tak
```

## Reverse Proxy with Nginx

TAK Server uses mutual TLS (mTLS) on most ports -- the client presents a certificate and the server validates it. This means **you cannot terminate TLS at the reverse proxy** for TAK protocol ports. Instead, Nginx acts as a **TCP/TLS passthrough** proxy.

### Understanding the Ports

| Port | Protocol | Proxy Mode | Purpose |
|------|----------|------------|---------|
| 8443 | HTTPS + mTLS | **TCP passthrough** | Web UI + API (client cert required) |
| 8089 | TLS + mTLS | **TCP passthrough** | ATAK/iTAK/WinTAK client connections |
| 8444 | HTTPS + mTLS | **TCP passthrough** | Federation |
| 8446 | HTTPS | **TCP passthrough** | Certificate enrollment (no client cert) |

> **Important:** Because TAK uses mTLS (mutual TLS), Nginx must use `stream` (L4 TCP proxy), NOT `http` (L7). The TLS handshake happens directly between the client and TAK Server.

### Install Nginx

```bash
sudo apt install -y nginx

# Ensure the stream module is available
nginx -V 2>&1 | grep -o with-stream
```

If `with-stream` is not shown, install the full version:

```bash
sudo apt install -y nginx-extras
```

### Nginx Configuration (SNI-Based Subdomain Routing)

TAK ports use TLS, so Nginx can read the **SNI (Server Name Indication)** field from the TLS ClientHello to determine which hostname the client is connecting to. This lets you:

- Only accept connections to `tak.yourdomain.com`
- Reject connections via the raw IP address or any other subdomain
- Run other services on the same VPS without conflicts

**Replace `tak.yourdomain.com` with your actual subdomain throughout.**

Create `/etc/nginx/nginx.conf`:

```nginx
# Main context
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

# TCP passthrough for TAK mTLS ports with SNI-based subdomain filtering
stream {
    log_format stream_log '$remote_addr [$time_local] '
                          '$protocol $status $bytes_sent $bytes_received '
                          '$session_time "$upstream_addr" '
                          'SNI="$ssl_preread_server_name"';

    access_log /var/log/nginx/stream_access.log stream_log;

    # ---- Upstream backends (kubectl port-forward targets) ----
    upstream tak_https    { server 127.0.0.1:18443; }
    upstream tak_ssl      { server 127.0.0.1:18089; }
    upstream tak_fed      { server 127.0.0.1:18444; }
    upstream tak_certenrl { server 127.0.0.1:18446; }

    # ---- SNI routing maps ----
    # Each map reads the SNI hostname and routes to the correct upstream.
    # Any hostname that does NOT match returns "" which causes Nginx to
    # close the connection immediately.

    map $ssl_preread_server_name $tak_https_backend {
        tak.yourdomain.com    tak_https;
        default               "";
    }

    map $ssl_preread_server_name $tak_ssl_backend {
        tak.yourdomain.com    tak_ssl;
        default               "";
    }

    map $ssl_preread_server_name $tak_fed_backend {
        tak.yourdomain.com    tak_fed;
        default               "";
    }

    map $ssl_preread_server_name $tak_certenrl_backend {
        tak.yourdomain.com    tak_certenrl;
        default               "";
    }

    # ---- Port 8443: Web UI / API (mTLS) ----
    server {
        listen 8443;
        listen [::]:8443;
        ssl_preread on;
        proxy_pass $tak_https_backend;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
    }

    # ---- Port 8089: ATAK/iTAK/WinTAK client connections (mTLS) ----
    server {
        listen 8089;
        listen [::]:8089;
        ssl_preread on;
        proxy_pass $tak_ssl_backend;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
    }

    # ---- Port 8444: Federation (mTLS) ----
    server {
        listen 8444;
        listen [::]:8444;
        ssl_preread on;
        proxy_pass $tak_fed_backend;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
    }

    # ---- Port 8446: Certificate Enrollment ----
    server {
        listen 8446;
        listen [::]:8446;
        ssl_preread on;
        proxy_pass $tak_certenrl_backend;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
    }
}

# HTTP block
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Reject requests to other subdomains / raw IP
    server {
        listen 80 default_server;
        server_name _;
        return 444;  # close connection with no response
    }

    # Your TAK subdomain - redirect HTTP to the HTTPS web UI
    server {
        listen 80;
        server_name tak.yourdomain.com;

        location / {
            return 301 https://tak.yourdomain.com:8443$request_uri;
        }

        location /health {
            return 200 'TAK Server is running\n';
            add_header Content-Type text/plain;
        }
    }
}
```

### How SNI Filtering Works

When a TLS client connects, it sends the hostname it wants in the SNI field **before encryption starts**. Nginx reads this with `ssl_preread on` and:

1. If SNI = `tak.yourdomain.com` -> proxies to the TAK backend
2. If SNI = anything else (other subdomain, raw IP, empty) -> the `map` returns `""` which makes `proxy_pass` fail, and Nginx **drops the connection**

This means:
- `https://tak.yourdomain.com:8443` -- works
- `https://123.45.67.89:8443` -- **dropped** (no SNI match)
- `https://other.yourdomain.com:8443` -- **dropped** (no SNI match)
- ATAK connecting to `tak.yourdomain.com:8089` -- works
- ATAK connecting to `123.45.67.89:8089` -- **dropped**

### Adding Multiple Subdomains

If you want to run multiple TAK servers or allow an alias, add entries to the maps:

```nginx
    map $ssl_preread_server_name $tak_https_backend {
        tak.yourdomain.com       tak_https;
        tak-backup.yourdomain.com tak_https;
        default                   "";
    }
```

### Port Forwarding from Kubernetes

Since Nginx proxies to `127.0.0.1:18443` etc., you need to forward the Kubernetes service ports to those local ports. Create a systemd service for this:

```bash
sudo tee /etc/systemd/system/tak-port-forward.service > /dev/null <<'EOF'
[Unit]
Description=TAK Server Kubernetes Port Forwards
After=k3s.service
Requires=k3s.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/kubectl port-forward svc/tak-server-tak-server-tak \
    18443:8443 18089:8089 18444:8444 18446:8446 \
    -n tak --address=127.0.0.1
Restart=always
RestartSec=5
Environment=KUBECONFIG=/etc/rancher/k3s/k3s.yaml

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tak-port-forward
sudo systemctl start tak-port-forward
```

Alternatively, with k3s you can change the service type to `LoadBalancer` which binds directly to the host:

```bash
# Edit values to use LoadBalancer instead of NodePort
helm upgrade tak-server ./helm/tak-server \
    --namespace tak \
    --set service.type=LoadBalancer \
    --reuse-values
```

With `LoadBalancer` on k3s, the ports bind directly to the host IP and you can skip the Nginx stream proxy entirely. However, using Nginx gives you:
- **SNI subdomain filtering** -- only `tak.yourdomain.com` is accepted, raw IP is rejected
- Request logging
- The ability to add an HTTP landing page
- Rate limiting capabilities

If you use `LoadBalancer` without Nginx, the ports are accessible via any hostname or raw IP.

### Test and Reload Nginx

```bash
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

## Subdomain Setup

### DNS Configuration

Point your subdomain to your VPS IP address:

```
Type: A
Name: tak
Value: <YOUR_VPS_IP>
TTL: 300

Type: AAAA (if IPv6)
Name: tak
Value: <YOUR_VPS_IPv6>
TTL: 300
```

This gives you `tak.yourdomain.com`.

### How Clients Connect

Since TAK uses mTLS with its own CA (not Let's Encrypt), the subdomain is used purely for DNS resolution. Clients connect like this:

- **Web UI:** `https://tak.yourdomain.com:8443` (import admin.p12 in browser)
- **ATAK/iTAK:** Server address `tak.yourdomain.com`, port `8089`, protocol `SSL`
- **Federation:** `tak.yourdomain.com:8444`

### What About Let's Encrypt?

TAK Server manages its own PKI (Public Key Infrastructure) with its own Certificate Authority. The `.p12` certificates generated during setup are what authenticate both server and client. **You do not need Let's Encrypt** for TAK Server ports.

However, if you want to add an informational landing page on port 443, you can use certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx

# Add an HTTP server block for your subdomain first, then:
sudo certbot --nginx -d tak.yourdomain.com
```

This would only apply to a standard HTTPS landing page, not to the TAK ports themselves.

### Data Package Configuration

When generating data packages for your EUDs, use your subdomain instead of an IP address. The `certDP.sh` script takes an IP parameter -- pass your domain name instead:

```bash
./scripts/certDP.sh tak.yourdomain.com user1
```

This creates a data package where ATAK connects to `tak.yourdomain.com:8089`.

## Firewall Configuration

### UFW (Ubuntu)

```bash
# Allow SSH
sudo ufw allow 22/tcp

# TAK Server ports
sudo ufw allow 8089/tcp    # ATAK/iTAK client connections
sudo ufw allow 8443/tcp    # Web UI
sudo ufw allow 8444/tcp    # Federation (only if federating)
sudo ufw allow 8446/tcp    # Certificate enrollment (only if needed)

# Optional: HTTP redirect
sudo ufw allow 80/tcp

# Enable firewall
sudo ufw enable
sudo ufw status
```

### iptables

```bash
# TAK ports
sudo iptables -A INPUT -p tcp --dport 8089 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8444 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8446 -j ACCEPT
```

### Security Notes

- **Do NOT expose port 5432** (PostgreSQL) -- it's internal to the cluster
- Ports 9000/9001 (WebSocket) are rarely needed -- only open if you use WebSocket clients
- Consider using a VPN (WireGuard/OpenVPN) instead of exposing ports publicly
- All TAK ports use TLS + mutual authentication, so they are encrypted and authenticated
- For maximum security, restrict source IPs with firewall rules

## Architecture Overview

```
Internet
    |
    v
[ DNS: tak.yourdomain.com -> VPS_IP ]
    |
    v
[ VPS Firewall (UFW) ]
    |
    +---> :8443 --> [ Nginx: SNI check ] -- tak.yourdomain.com --> :18443 --> [ k8s ] --> [ TAK Pod ]
    |                                    \-- other/IP -----------> DROPPED
    |
    +---> :8089 --> [ Nginx: SNI check ] -- tak.yourdomain.com --> :18089 --> [ k8s ] --> [ TAK Pod ]
    |                                    \-- other/IP -----------> DROPPED
    |
    +---> :8444 --> [ Nginx: SNI check ] -- tak.yourdomain.com --> :18444 --> [ k8s ] --> [ TAK Pod ]
    +---> :8446 --> [ Nginx: SNI check ] -- tak.yourdomain.com --> :18446 --> [ k8s ] --> [ TAK Pod ]
    |
    +---> :80   --> [ Nginx HTTP ] -- tak.yourdomain.com --> redirect to :8443
                                   \-- other -----------> 444 (dropped)

Inside Kubernetes (k3s):
    [ TAK Server Pod ] <----> [ PostgreSQL/PostGIS Pod ]
           |                          |
    [ PVC: tak-data ]          [ PVC: db-data ]
```

With `LoadBalancer` service type on k3s (simpler, no Nginx, no SNI filtering):

```
Internet
    |
    v
[ DNS: tak.yourdomain.com -> VPS_IP ]
    |
    v
[ VPS Firewall (UFW) ]
    |
    +---> :8443 --> [ k3s ServiceLB ] --> [ TAK Pod :8443 ]  (accessible via ANY hostname/IP)
    +---> :8089 --> [ k3s ServiceLB ] --> [ TAK Pod :8089 ]
    +---> :8444 --> [ k3s ServiceLB ] --> [ TAK Pod :8444 ]
    +---> :8446 --> [ k3s ServiceLB ] --> [ TAK Pod :8446 ]
```

## Backups

### Database Backup

```bash
# Get the database pod name
DB_POD=$(kubectl get pods -n tak -l app.kubernetes.io/component=database -o jsonpath='{.items[0].metadata.name}')

# Dump the database
kubectl exec -n tak $DB_POD -- pg_dump -U martiuser cot > tak-backup-$(date +%Y%m%d).sql
```

### Certificate Backup

```bash
# Copy certs from the TAK pod
TAK_POD=$(kubectl get pods -n tak -l app.kubernetes.io/component=takserver -o jsonpath='{.items[0].metadata.name}')
kubectl cp tak/$TAK_POD:/opt/tak/certs/files/ ./backup-certs-$(date +%Y%m%d)/
```

### Full PVC Backup

```bash
# Create a backup pod that mounts both PVCs
kubectl apply -n tak -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: backup-pod
spec:
  restartPolicy: Never
  containers:
    - name: backup
      image: busybox
      command: ["sh", "-c", "tar czf /backup/tak-data.tar.gz -C /opt/tak . && tar czf /backup/db-data.tar.gz -C /var/lib/postgresql/data . && sleep 3600"]
      volumeMounts:
        - name: tak-data
          mountPath: /opt/tak
          readOnly: true
        - name: db-data
          mountPath: /var/lib/postgresql/data
          readOnly: true
        - name: backup
          mountPath: /backup
  volumes:
    - name: tak-data
      persistentVolumeClaim:
        claimName: tak-server-tak-server-tak-data
    - name: db-data
      persistentVolumeClaim:
        claimName: tak-server-tak-server-db-data
    - name: backup
      hostPath:
        path: /tmp/tak-backup
EOF

# Wait for backup to complete
kubectl wait --for=condition=Ready pod/backup-pod -n tak --timeout=120s
sleep 10

# Copy backup files
kubectl cp tak/backup-pod:/backup/ ./tak-full-backup-$(date +%Y%m%d)/

# Clean up
kubectl delete pod backup-pod -n tak
```

### Automated Backup Cron

```bash
# Add to crontab (daily at 2 AM)
crontab -e
```

```cron
0 2 * * * /home/tak/tak-server/scripts/backup.sh >> /var/log/tak-backup.log 2>&1
```

## Monitoring

### Quick Health Check

```bash
# Pod status
kubectl get pods -n tak

# Resource usage
kubectl top pods -n tak

# Logs
kubectl logs -f deployment/tak-server-tak-server-tak -n tak

# Database logs
kubectl logs -f deployment/tak-server-tak-server-db -n tak
```

### Check Nginx Proxy

```bash
# Nginx status
sudo systemctl status nginx

# Stream proxy logs
sudo tail -f /var/log/nginx/stream_access.log

# Port forward status
sudo systemctl status tak-port-forward
```

### Simple Uptime Monitor

```bash
# Check if TAK is responding (from outside, using client cert)
curl -k --cert admin.p12:atakatak https://tak.yourdomain.com:8443/Marti/api/version
```

## Troubleshooting

### Pods not starting

```bash
kubectl describe pods -n tak
kubectl logs -n tak <pod-name>
```

### Nginx "connection refused"

Ensure port-forward service is running:
```bash
sudo systemctl status tak-port-forward
sudo journalctl -u tak-port-forward -f
```

### Can't reach from outside

```bash
# Check firewall
sudo ufw status

# Check ports are listening
sudo ss -tlnp | grep -E '8443|8089|8444|8446'

# Test locally first
curl -k https://127.0.0.1:8443
```

### ATAK won't connect

1. Ensure DNS resolves: `nslookup tak.yourdomain.com`
2. Ensure port 8089 is open: `nc -zv tak.yourdomain.com 8089`
3. Check the data package was generated with the correct hostname
4. Verify client certificate was imported correctly in ATAK

### k3s-specific issues

```bash
# Check k3s status
sudo systemctl status k3s

# k3s logs
sudo journalctl -u k3s -f

# If images aren't found, import them manually
docker save tak-server:latest | sudo k3s ctr images import -
docker save tak-server-db:latest | sudo k3s ctr images import -
```
