# Contributing

Pull requests are welcome. For larger changes, open an issue first to discuss the approach.

## Development checks

Run these before opening a PR (CI runs the same checks):

```bash
helm lint helm/tak-server --strict
helm template tak-server helm/tak-server --namespace tak > /dev/null
shellcheck --severity=warning scripts/*.sh
```

## Testing a change end-to-end

1. Place a TAK Server Docker release ZIP from [tak.gov](https://tak.gov/products/tak-server) in the repo root.
2. Run `./scripts/setup.sh` against a throwaway cluster (k3s, minikube, kind, or Docker Desktop).
3. Run `./scripts/cleanup.sh` when done.

Mention the cluster type, architecture, and TAK release you tested with in the PR description.

## Adding checksums for a new TAK release

Add the release to **both** `tak-md5checksum.txt` and `tak-sha1checksum.txt`, and to the
table in `README.md`. Only use checksums published by the TAK Product Center.

## Commit style

[Conventional Commits](https://www.conventionalcommits.org/) are preferred
(`feat:`, `fix:`, `docs:`, `chore:`, ...). Update `CHANGELOG.md` under **Unreleased** for
user-facing changes.
