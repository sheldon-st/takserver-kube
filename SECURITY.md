# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems in this repository's
Helm chart, Dockerfiles, or scripts.

Report them privately via
[GitHub Security Advisories](https://github.com/sheldon-st/takserver-kube/security/advisories/new).
Include steps to reproduce and the affected TAK Server release if relevant.

## Scope

- **In scope:** the Helm chart, Dockerfiles, setup / certificate scripts, and default
  configuration shipped in this repo.
- **Out of scope:** vulnerabilities in TAK Server itself. Report those to the
  [TAK Product Center](https://tak.gov/). Older TAK releases contain known
  vulnerabilities; always run the newest release available.

## Hardening notes

- Change the default certificate password (`atakatak`) for anything beyond local testing.
- `scripts/shareCerts.sh` serves certificates over **unauthenticated HTTP**. Use it only
  on a trusted network and stop it as soon as devices are enrolled.
- Never commit `.p12`, `.pem`, `.jks`, or `tak/` output to git (they are in `.gitignore`).
