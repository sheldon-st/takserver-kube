# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- GitHub issue forms, PR template, CI (Helm lint/template, ShellCheck, checksum list sync), and Dependabot.
- `SECURITY.md`, `CONTRIBUTING.md`, `.editorconfig`.
- Helm chart metadata (`home`, `sources`, `keywords`, `maintainers`, `icon`, `kubeVersion`) and standard
  `helm.sh/chart` / `app.kubernetes.io/version` labels.

### Changed

- README and FAQ updated for this repository (clone URL, k3s support, paths, removed dead links).

## [1.0.0] - 2026-04-07

Kubernetes / Helm rewrite of the Docker Compose wrapper.

### Added

- Helm chart (`helm/tak-server`) deploying TAK Server and PostGIS with persistent volumes.
- `scripts/setup.sh`: checksum verification, image build, image loading for k3s / minikube / kind,
  Helm deploy, certificate and account bootstrap.
- `scripts/makeCert.sh` (client and `--admin` certs + data packages), `scripts/shareCerts.sh`,
  `scripts/cleanup.sh`.
- AMD64 and ARM64 Dockerfiles.

### Changed

- Removed Docker Compose workflow in favor of Kubernetes.

## Upstream history

This project began from the Docker Compose wrapper by
[Cloud-RF/tak-server](https://github.com/Cloud-RF/tak-server). Notable upstream milestones:

- **2025-10-06** — Checksums for 5.4 REL 106 and 5.5 REL 58; NIC selection.
- **2025-07-13** — 5.4 REL 19 support; license changed from GPL-3.0 to MIT.
- **2022-11-24** — 7zip support, automatic CA generation, Postgres connection limit raised to 400.
- **2022-11-23** — Reduced Postgres memory, mini web server for data packages, fixed HTTPS startup race.
- **2022-10-18** — Automatic user certificates and data packages.
- **2022-08-17** — Automatic SSL setup, HTTPS only, insecure protocols removed.
