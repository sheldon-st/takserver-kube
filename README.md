# TAK Server on Kubernetes

[![CI](https://github.com/sheldon-st/takserver-kube/actions/workflows/ci.yml/badge.svg)](https://github.com/sheldon-st/takserver-kube/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Helm](https://img.shields.io/badge/helm-v3-0F1689?logo=helm)
![TAK Server](https://img.shields.io/badge/TAK%20Server-5.x-2E7D32)
![Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-lightgrey)

![TAK logo](img/tak.jpg)

A Kubernetes / Helm wrapper for the official TAK Server from the [TAK Product Center](https://tak.gov/). Provides a turnkey TAK Server with SSL and PostGIS that works with ATAK, iTAK, and WinTAK, on k3s, minikube, kind, Docker Desktop, or a managed cluster.

## Contents

- [Download the Official TAK Release](#download-the-official-tak-release)
- [Requirements](#requirements)
- [Installation](#installation)
- [Admin Login](#admin-login)
- [Web UI Access](#web-ui-access)
- [Common Commands](#common-commands)
- [Adding Your First EUD / ATAK Device](#adding-your-first-eud--atak-device)
- [Repository Layout](#repository-layout)
- [FAQ](#faq)

## Download the Official TAK Release

Before you can build this, you must download a **TAKSERVER-DOCKER-X.X-RELEASE** ZIP.

Releases are available at [https://tak.gov/products/tak-server](https://tak.gov/products/tak-server). Register for an account, then download from the link above.

The integrity of the release will be checked during setup against the MD5/SHA1 checksums in this repo. **These must match.** If they do not, **do not proceed** unless you trust the source.

Old releases contain known vulnerabilities. For more information, see the notices on tak.gov.

![TAK release download](img/tak-server-download.jpg)

## Release Checksums

| Release Filename                       | Size    | MD5                                | SHA1                                       |
| -------------------------------------- | ------- | ---------------------------------- | ------------------------------------------ |
| `takserver-docker-5.2-RELEASE-30.zip`  | `517MB` | `b691d1d7377790690e1e5ec0e4a29a56` | `98f13f9140470ee65351e3d25dec097603bfb582` |
| `takserver-docker-5.2-RELEASE-43.zip`  | `517MB` | `0a7398383253707dd7564afc88f29b3b` | `824d7b89fbe6377cb5570f50bb35e6e05c12b230` |
| `takserver-docker-5.3-RELEASE-24.zip`  | `527MB` | `e8a5dc855c4eb67d170bf689017516e8` | `1eaad8c4471392a96c60f56bc2d54f9f3b6d719e` |
| `takserver-docker-5.3-RELEASE-30.zip`  | `527MB` | `b24b5ae01aeac151565aa35a39899785` | `37c3a8f3c7626326504ab8047c42a0473961be24` |
| `takserver-docker-5.4-RELEASE-19.zip`  | `522MB` | `9e6f3e3b61f8677b491d6ed15baf1813` | `2f3ced9b3e81c448e401b995f64566e7b888b991` |
| `takserver-docker-5.4-RELEASE-106.zip` | `522MB` | `edce00ff13f8fdfb340e7e05eafc5454` | `7f7da1a58544b34e01576b99f8db59e1987cd96c` |
| `takserver-docker-5.5-RELEASE-58.zip`  | `531MB` | `6d362f234305b9a5e8f9245ef8f3e45d` | `7f0c07aa0ad7ff575c0278d734264e3e446ec93c` |

The full list used by `setup.sh` (including 5.0 and 5.1) is in [`tak-md5checksum.txt`](tak-md5checksum.txt) and [`tak-sha1checksum.txt`](tak-sha1checksum.txt).

## Requirements

- **macOS** or **Linux** (Debian, Ubuntu, etc.)
- A Kubernetes cluster (local or remote):
  - [k3s](https://k3s.io/) (images are imported into containerd automatically)
  - [Docker Desktop with Kubernetes](https://docs.docker.com/desktop/kubernetes/)
  - [minikube](https://minikube.sigs.k8s.io/docs/start/)
  - [kind](https://kind.sigs.k8s.io/)
  - Any cloud-managed cluster (EKS, GKE, AKS)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Docker](https://docs.docker.com/engine/install/) (for building images)
- A TAK server release ZIP file
- 4GB memory
- Network connection
- `unzip` utility

## Prerequisites

Install the required tools for your platform, then clone the repo:

### macOS

```bash
brew install kubectl helm
# Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/
git clone https://github.com/sheldon-st/takserver-kube.git
cd takserver-kube
```

### Linux (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install unzip zip
# Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
# Install helm: https://helm.sh/docs/intro/install/
# Install Docker: https://docs.docker.com/engine/install/
git clone https://github.com/sheldon-st/takserver-kube.git
cd takserver-kube
```

### Setting Up a Local Kubernetes Cluster

If you don't already have a Kubernetes cluster, the easiest option is Docker Desktop with Kubernetes enabled, or minikube:

```bash
# Option A: Docker Desktop - Enable Kubernetes in Docker Desktop Settings > Kubernetes

# Option B: minikube
brew install minikube   # macOS
minikube start --memory 4096
```

### AMD64 & ARM64 (Apple Silicon / Pi4) Support

The setup script auto-detects your architecture and uses the appropriate Dockerfile.

## Installation

Copy your downloaded **TAKSERVER-DOCKER-X.X-RELEASE** ZIP file to the repository root, then run:

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The setup script will:

1. Verify the release checksum
2. Build Docker images for the TAK server and PostgreSQL database
3. Deploy to Kubernetes using Helm
4. Generate SSL certificates
5. Create admin and user accounts
6. Output credentials and access information

### NIC Selection

The interactive network interface prompt requires you to select your interface. Ensure this is the interface on which you want clients to access the service.

### Network Ports

TAK server needs the following ports:

- `8089` - SSL/TLS (client connections)
- `8443` - HTTPS (Web UI)
- `8444` - Federation HTTPS
- `8446` - Certificate enrollment HTTPS
- `9000` - WebSocket Secure
- `9001` - WebSocket

### Successful Installation

A successful installation will display:

```
========================================
  TAK Server Setup Complete
========================================

Import admin.p12 to your browser's certificate store (password: atakatak)

Web UI: https://<your-ip>:8443

---------CREDENTIALS---------

Admin username:     admin
Admin password:     <generated>
PostgreSQL password: <generated>

-----------------------------

SAVE THESE CREDENTIALS NOW. They will not be shown again.
```

## Admin Login

The web interface login requires the certificate created during setup. Default certificate name is `admin.p12`.

To list certificates:

```bash
kubectl exec -it -n tak deployment/tak-server-tak-server-tak -- ls -hal /opt/tak/certs/files
```

### Installing Your Admin Certificate

The `admin.p12` certificate needs to be copied from `./tak/certs/files/` and installed in a web browser.

#### Google Chrome

- Go to **Settings** > **Privacy and Security** > **Security** > **Manage Certificates**
- Navigate to **Your certificates**
- Click **Import** and choose your `.p12` file (password: `atakatak`)

#### Mozilla Firefox

- Go to **Settings** > **Privacy & Security** > scroll down to **Certificates**
- Click **View Certificates**
- Under **Your Certificates**, click **Import** and select your `.p12` certificate (password: `atakatak`)
- Under **Authorities**, find **TAK** and your certificate name
- Click **Edit Trust** and check **This certificate can identify web sites**, then click **OK**

## Web UI Access

The web UI is accessible via HTTPS on port 8443:

```
https://localhost:8443
```

If using NodePort, the port may differ:

```bash
kubectl get svc -n tak
```

Or use port-forwarding:

```bash
kubectl port-forward svc/tak-server-tak-server-tak 8443:8443 -n tak
kubectl port-forward svc/tak-server-tak-server-tak 8443:8443 8089:8089 8444:8444 8446:8446 9000:9000 9001:9001 -n tak

```

## Common Commands

```bash
# Check pod status
kubectl get pods -n tak

# View logs
kubectl logs -f deployment/tak-server-tak-server-tak -n tak

# Shell into TAK server
kubectl exec -it -n tak deployment/tak-server-tak-server-tak -- bash

# Clean up everything
./scripts/cleanup.sh
```

## Adding Your First EUD / ATAK Device

Ready-made data packages are in `tak/certs/files/`. Copy a `.zip` to your device and import it into ATAK / iTAK using the "Import" function.

This adds a server connection, certificates, and a user account. You still need to create this user with a matching name in the TAK server user management dashboard and assign them to a group.

## Creating Additional Certificates

```bash
# Generate ATAK/iTAK client cert + data package
./scripts/makeCert.sh user3 192.168.1.100

# Generate an admin cert (required for web UI access on port 8443)
./scripts/makeCert.sh webadmin 192.168.1.100 --admin
```

The `--admin` flag is required for users who need to access the web UI. Without it, the cert only works for ATAK/iTAK device connections.

## Federated TAK Server

To federate TAK servers, exchange `ca.pem` files between servers and add them to `fed-truststore.jks`:

```bash
keytool -importcert -file ca.pem -keystore tak/certs/files/fed-truststore.jks -alias "tak"
```

### Transferring User Certificates via HTTP

You can temporarily serve `.zip` data packages on TCP port 12345 for device setup. **Only use this on a trusted network** — it is unencrypted.

```bash
./scripts/shareCerts.sh
```

Stop with `Ctrl-C` once transferred. For secure transfer, copy to the device via USB.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `helm/tak-server/` | Helm chart (TAK Server + PostGIS deployments, services, PVCs) |
| `docker/{amd64,arm64}/` | Dockerfiles for the TAK Server and database images |
| `scripts/` | `setup.sh`, `makeCert.sh`, `certDP.sh`, `shareCerts.sh`, `cleanup.sh` |
| `CoreConfig.xml` | TAK Server configuration applied during setup |
| `tak-*checksum.txt` | Known-good release checksums verified by `setup.sh` |
| `tak/` | Generated at runtime (certs, data packages); git-ignored |

## FAQ

See [Frequently Asked Questions](FAQ.md).

## Contributing

Pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). For security issues, see [SECURITY.md](SECURITY.md).

## Authors and Acknowledgment

Thanks to the TAK Product Center for open-sourcing and maintaining all things TAK.

This project is a Kubernetes adaptation of the Docker Compose wrapper by [Cloud-RF/tak-server](https://github.com/Cloud-RF/tak-server), which in turn built on the Docker wrapper published by James Wu 'wubar' on GitLab/Discord.

## Useful Links

- [TAK server on TAK.gov](https://tak.gov/products/tak-server)
- [ATAK-CIV on Google Play](https://play.google.com/store/apps/details?id=com.atakmap.app.civ&hl=en_GB&gl=US)
- [iTak on Apple App Store](https://apps.apple.com/my/app/itak/id1561656396)
- [WinTAK-CIV on TAK.gov](https://tak.gov/products/wintak-civ)
