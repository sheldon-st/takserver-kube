# TAK SERVER

![TAK logo](img/tak.jpg)

This is a Kubernetes/Helm wrapper for an official 'OG' TAK server from [TAK Product Center](https://tak.gov/) intended for beginners. It will give you a turnkey TAK server with SSL which works with ATAK, iTAK, WinTAK.


## IMPORTANT: Download the Official TAK Release

Before you can build this, you must download a **TAKSERVER-DOCKER-X.X-RELEASE**.

Releases are now public at [https://tak.gov/products/tak-server](https://tak.gov/products/tak-server)

Please follow account registration process, and once completed go to the link above.

The integrity of the release will be checked at setup against the MD5/SHA1 checksums in this repo. **THESE MUST MATCH**. If they do not match, **DO NOT** proceed unless you trust the release.

Old releases are a security risk as they contain known vulnerabilities. For more information, read the big red notices on tak.gov

![TAK release download](img/tak-server-download.jpg)

## TAK Server Release Checksums

| Release Filename                      | Bytes       | MD5 Checksum                       | SHA1 Checksum                              |
| ------------------------------------- | ----------- | ---------------------------------- | ------------------------------------------ |
| `takserver-docker-5.2-RELEASE-30.zip`| `517MB` | `b691d1d7377790690e1e5ec0e4a29a56` | `98f13f9140470ee65351e3d25dec097603bfb582` |
| `takserver-docker-5.2-RELEASE-43.zip`| `517MB` | `0a7398383253707dd7564afc88f29b3b` | `824d7b89fbe6377cb5570f50bb35e6e05c12b230` |
| `takserver-docker-5.3-RELEASE-24.zip`| `527MB` | `e8a5dc855c4eb67d170bf689017516e8` | `1eaad8c4471392a96c60f56bc2d54f9f3b6d719e` |
| `takserver-docker-5.3-RELEASE-30.zip`| `527MB` | `b24b5ae01aeac151565aa35a39899785` | `37c3a8f3c7626326504ab8047c42a0473961be24` |
| `takserver-docker-5.4-RELEASE-19.zip` | `522MB` | `9e6f3e3b61f8677b491d6ed15baf1813` | `2f3ced9b3e81c448e401b995f64566e7b888b991` |
| `takserver-docker-5.4-RELEASE-106.zip` | `522MB` | `edce00ff13f8fdfb340e7e05eafc5454` | `7f7da1a58544b34e01576b99f8db59e1987cd96c` |
| `takserver-docker-5.5-RELEASE-58.zip` | `531MB` | `6d362f234305b9a5e8f9245ef8f3e45d` | `7f0c07aa0ad7ff575c0278d734264e3e446ec93c` |

## Requirements

- **macOS** or **Linux** (Debian, Ubuntu, etc.)
- A Kubernetes cluster (local or remote):
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
git clone https://github.com/Cloud-RF/tak-server.git
cd tak-server
```

### Linux (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install unzip zip
# Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
# Install helm: https://helm.sh/docs/intro/install/
# Install Docker: https://docs.docker.com/engine/install/
git clone https://github.com/Cloud-RF/tak-server.git
cd tak-server
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

The script auto-detects your architecture and uses the appropriate Dockerfile.

## Installation

Copy your downloaded **TAKSERVER-DOCKER-X.X-RELEASE** ZIP file to the `tak-server` directory, then run:

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The `setup.sh` script will:
1. Verify the release checksum
2. Build Docker images for the TAK server and PostgreSQL database
3. Deploy to Kubernetes using Helm
4. Generate SSL certificates
5. Create admin and user accounts
6. Output credentials and access information

### NIC Selection
The interactive network interface prompt requires you to select your interface. Ensure this is the interface on which you want clients to access the service.

### Network Ports

TAK server needs the following port numbers to operate:

- `8089` - SSL/TLS
- `8443` - HTTPS (Web UI)
- `8444` - Federation HTTPS
- `8446` - Certificate HTTPS
- `9000` - WebSocket Secure
- `9001` - WebSocket

### Successful Installation

If your TAK Server was able to successfully be installed then you should see a message similar to:

```console
Import the admin.p12 certificate from this folder to your browser as per the README.md file
Login at https://10.0.0.6:8443 with your admin account. No need to run the /setup step as this has been done.
Certificates and .zip data packages are in tak/certs/files

Setup script sponsored by CloudRF.com - "The API for RF"

---------PASSWORDS----------------

Admin user name: admin
Admin password: <Your password here>
Postgresql password: <Your password here>

---------PASSWORDS----------------

MAKE A NOTE OF YOUR PASSWORDS. THEY WON'T BE SHOWN AGAIN.
Kubernetes namespace: tak
Helm release: tak-server
```

## Admin Login

The login to the web interface requires the certificate created during setup. Default certificate name is `admin.p12`.

To list certificates:

```bash
kubectl exec -it -n tak deployment/tak-server-tak-server-tak -- ls -hal /opt/tak/certs/files
```

### Installing Your Admin Certificate

The `admin.p12` certificate needs to be copied from `./tak/certs/files/` and installed in a web browser.

#### Google Chrome

* Go to **"Settings"** --> **"Privacy and Security"** --> **"Security"** --> **"Manage Certificates"**
* Navigate to **"Your certificates"**
* Press **"Import"** button and choose your `.p12` file (Default password is `atakatak`)

#### Mozilla Firefox

* Go to **"Settings"** --> **"Privacy & Security"** --> scroll down to **"Certificates"** section.
* Click the button **"View Certificates"**
* Choose **"Your Certificates"** section and **"Import"** your `.p12` certificate (Default password is `atakatak`)
* Choose the **"Authorities"** section
* Locate **"TAK"** line, there should be your certificate name displayed underneath it
* Click your certificate name and press button **"Edit Trust"**
* __*TICK*__ the box with **"This certificate can identify web sites"** statement, then click **"OK"**

## Web UI Access

The web user interface can be only accessed via **SSL** on port **8443**.

`https://localhost:8443`

If using NodePort, the port may differ. Check with:

```bash
kubectl get svc -n tak
```

Or use port-forwarding:

```bash
kubectl port-forward svc/tak-server-tak-server-tak 8443:8443 -n tak
```

### Checking Pod Status

```bash
kubectl get pods -n tak
```

### Viewing Logs

```bash
kubectl logs -f deployment/tak-server-tak-server-tak -n tak
```

### Accessing a Shell in the TAK Pod

```bash
kubectl exec -it -n tak deployment/tak-server-tak-server-tak -- bash
```

### Clean Up

```bash
sudo ./scripts/cleanup.sh
```

This script will uninstall the Helm release, delete PVCs, remove the namespace, and clean up local files.

**WARNING** - If you have data in an existing TAK database it will be lost.

## Adding Your First EUD / ATAK Device

You can find ready made data packages in the `tak/certs/files` directory. Copy these to your device's SD card then import the `.zip` into ATAK / iTAK with the "Import" function and choose "Local SD".

This will add a server, certificates and a user account. You will still need to create this user with the matching name in your TAK server user management dashboard and assign them to a common group.

## Federated TAK server

If you would like to federate TAK servers you will need to exchange ca.pem files between servers to the fed-truststore.jks file:

```bash
keytool -importcert -file ca.pem -keystore tak-server/tak/certs/files/fed-truststore.jks -alias "tak"
```

### Transferring user certificates via HTTP

You can run a script to serve the `.zip` files on TCP port `12345`. Only do this on a trusted network as it is not encrypted.

**Sharing certificates via insecure protocols is not recommended best practice. For a secure method, copy it to the SD card with a USB cable**

```bash
./scripts/shareCerts.sh
```

Stop the script with `Ctrl-C` once transferred.

# Production Deployment

For deploying to a VPS with a reverse proxy, subdomain, firewall, and backups, see the [Production Deployment Guide](PRODUCTION.md).

# FAQ

See [Frequently Asked Questions](FAQ.md).

## Contributing

Please feel free to open merge requests. A beginner's guide to GitHub.com is here:

https://www.freecodecamp.org/news/how-to-make-your-first-pull-request-on-github-3/

## Authors and Acknowledgment

Thanks to the TAK product center for open-sourcing and maintaining all things TAK.

Thanks to James Wu 'wubar' on GitLab/Discord for publishing the Docker wrapper on which this was built.

Thanks to protectionist dinosaurs, on both sides of the pond, who are threatened by TAK's open source model for the motivation :p

## Useful Links

- [TAK server on TAK.gov](https://tak.gov/products/tak-server)
- [ATAK-CIV on Google Play](https://play.google.com/store/apps/details?id=com.atakmap.app.civ&hl=en_GB&gl=US)
- [iTak on Apple App store](https://apps.apple.com/my/app/itak/id1561656396)
- [WinTAK-CIV on TAK.gov](https://tak.gov/products/wintak-civ)
