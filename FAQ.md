# FREQUENTLY ASKED QUESTIONS

## Where are the docs?

You can find the PDF manual in the tak/docs folder and get help from *community volunteers* via the TAK Discord server. If you ask a bone FAQ already covered in the manual, or demand urgent assistance, expect to get some grief. **RTFM and be patient**.

## How do I start over?
```
sudo ./scripts/cleanup.sh
```

This script will uninstall the Helm release, delete PVCs, remove the Kubernetes namespace, and clean up local files.

WARNING: If you have data in an existing TAK database it will be lost.

## How do I make a new certificate for my EUDs?

You can generate certificates using kubectl exec:

```bash
kubectl exec -it -n tak deployment/tak-server-tak-server-tak -- bash -c "cd /opt/tak/certs && ./makeCert.sh client EUD1"
```

Then copy the certificate locally:

```bash
kubectl cp tak/$(kubectl get pods -n tak -l app.kubernetes.io/component=takserver -o jsonpath='{.items[0].metadata.name}'):/opt/tak/certs/files/EUD1.p12 ./tak/certs/files/EUD1.p12
```

## Why does my EUD not connect?
Ensure you have created EUD certificates and have configured the following properly on your ATAK server settings:

- Address: Can you reach this with a browser on Android? If not - fix your network.
- Protocol: SSL
- Server Port: 8089
- Uncheck "Use default SSL/TLS Certificates"
- Import truststore-root.p12 to "Import Trust Store" with password atakatak
- Import {user}.p12 to "Import Client Certificate" with the name you chose during setup and the same password

On the server check:

- You have added a user eg. EUD1 https://takserver:8443/user-management/index.html#!/
- You have created a certificate for this user with the same name/callsign

## How do I enable Certificate Enrollment?

Visit https://localhost:8443/Marti/security/index.html#!/modifySecConfig and click Edit.
Enable "Enable Certificate Enrollment" and then Submit.

## I can't import the certificate to my browser?
Ensure the admin.p12 file is owned by you. Use the atakatak password when prompted and enable the TAK authority to "authenticate websites" in Firefox.

## How do I check pod status?
```bash
kubectl get pods -n tak
```

## How do I view logs?
```bash
kubectl logs -f deployment/tak-server-tak-server-tak -n tak
```

## How do I access a shell in the TAK server?
```bash
kubectl exec -it -n tak deployment/tak-server-tak-server-tak -- bash
```

## How do I port-forward to access the UI?
```bash
kubectl port-forward svc/tak-server-tak-server-tak 8443:8443 -n tak
```

Then access https://localhost:8443

## How can I upload a data package to Marti sync?
A successful POST will return a JSON message containing a SHA256 hash. This hash is the unique filename on the server.

### Upload

    curl 'https://127.0.0.1:8443/Marti/sync/upload' \
    --cert ssl/user.pem:atakatak \
    --key ssl/user.key \
    --cacert ssl/ca.pem \
    -F assetfile=@BIGPLAN.MK2.zip \
    -F Name=BIGPLAN.MK2 \
    -k -v

### Download

    https://takserver:8443/Marti/sync/content?hash=a10f4b65b27fd9ce047bf7c94f5841a503d1910d76cd156f749c4ff69e90ac33

## Why was the license changed

The GPL3.0 license was replaced with the more permissive MIT license in July 2025 since we learnt lawyers were making an unreasonable amount of amendments to Tak Server's GPL3.0 section 7 (Additional Terms) to further complicate the already complex licensing situtation.

We replaced the complex GPL3.0 license with a simple one which doesn't obligate users to do anything (or require input from a lawyer).

# Known issues

## Pods not starting / CrashLoopBackOff
Check pod logs with `kubectl logs -n tak <pod-name>`. Common causes:
- PVC not bound (check storage class)
- Image not available (ensure Docker images were built)
- Insufficient resources (check node capacity)

## Failed to initialize pool: Connection to tak-database:5432 refused
The database pod may not be ready yet. Check with `kubectl get pods -n tak` and wait for all pods to be Running.

## The login screen doesn't take my password?
Just wait a minute or two. This is expected behaviour due to the time the backend processes take to start up.

## Running the /setup wizard breaks the database?
This script **is the wizard** so it gets you past the setup wizard and populates the database tables. Only run the wizard if you know what you're doing.

## My custom logo doesn't show up?
Refresh your browser's cache with Ctrl-F5.
