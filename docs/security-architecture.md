# Security Architecture

## Layers

1. Edge and network enforcement
- `GL.iNet Flint 3` handles routing, VLANs, firewall policy, and `netifyd` traffic classification.
- Public ingress is limited to explicitly exposed services.

2. Ingress and identity
- `Caddy` is the single ingress proxy.
- `Authelia` protects interactive applications.
- Management-only services remain restricted to LAN/Tailscale where practical.

3. Secrets and infra control
- `Infisical` is the source of truth for long-lived app and automation secrets.
- `Terraform` or `OpenTofu` manages external APIs and infra metadata.

4. Runtime detection and response
- `Wazuh` correlates host, application, and integration logs.
- `CrowdSec` turns ingress logs into deny decisions.
- `Prometheus` and `Alertmanager` cover health and deadman-style security alerts.

5. Supply chain and configuration assurance
- `Trivy` scans container images, repo filesystems, and configuration/IaC.
- `Renovate` reduces drift across images and dependencies.

## Data Flow

### Public service exposure
Internet -> `Flint 3` firewall/NAT -> `Caddy` -> internal service

### Secret delivery
`Infisical` -> CLI export/render scripts -> generated runtime dotenv/config -> `docker compose`

### Alerting
Service logs and metrics -> `Wazuh` / `Prometheus` -> `Alertmanager` -> `alert-relay` / `ntfy` / Telegram

### Infrastructure intent
`infra/terraform/data/*.yaml` -> Terraform/OpenTofu plan -> Cloudflare/Tailscale control planes

## Operating Principles

- Treat repo-tracked files as templates and metadata, not secret stores.
- Prefer explicit exposure classes: `public`, `management-only`, `tailscale-only`, `internal`.
- Keep router-enforced zones simple and auditable.
- Validate before deploy: Terraform fmt/validate, Trivy scans, compose validation.
