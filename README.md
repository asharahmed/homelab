<p align="center">
  <img src="logo.svg" width="220" alt="Ashar Homelab mark"/>
</p>

<h1 align="center">Homelab</h1>

<p align="center">
  Public mirror of a private homelab focused on access control, observability, and security operations.
</p>

<p align="center">
  <a href="https://asharahmed.github.io/homelab/"><strong>Interactive overview</strong></a>
  ·
  <a href="https://github.com/asharahmed"><strong>GitHub profile</strong></a>
</p>

## What this repo is

This is the cleaned-up public version of the homelab I run day to day.

The live stack runs on Windows 11 with Docker Desktop and WSL2. I use it to test how I want services exposed, how I want authentication enforced, how I want telemetry collected, and how I want operational changes to be documented.

I did not want the public repo to be a screenshot gallery or a long service list. The point is to show how the system is put together.

## What I optimized for

- a single ingress layer instead of scattered direct exposure
- consistent authentication in front of sensitive services
- metrics, logs, and alerts that are actually tied together
- less secret sprawl and fewer hand-edited runtime values
- enough documentation that someone else can understand the shape of the system

## Core stack

**Edge and access**
- Caddy
- Authelia
- Tailscale

**Observability**
- Prometheus
- Alertmanager
- Grafana
- Loki
- Promtail
- Blackbox Exporter
- Uptime Kuma

**Security**
- CrowdSec
- Wazuh
- Velociraptor
- Trivy
- Renovate

**Platform**
- Infisical
- OpenTofu / Terraform
- Docker Compose

## What’s in the public mirror

- [index.html](index.html): the GitHub Pages project page
- [docker-compose.public.yml](docker-compose.public.yml): a representative Compose layout for the public-facing parts of the stack
- [Caddyfile.public](Caddyfile.public): a scrubbed Caddy config showing the ingress and auth model
- [docs/security-architecture.md](docs/security-architecture.md): the layered security model
- [infra/terraform](infra/terraform): external DNS and infrastructure metadata scaffold
- [scripts](scripts): selected bootstrap, validation, and security workflow scripts
- [tools/monitoring](tools/monitoring): monitoring examples with private and download-specific parts removed
- [artifacts/homepage-theme](artifacts/homepage-theme): sanitized dashboard design artifacts

## Representative architecture

```text
Internet
  -> Caddy
  -> CrowdSec / policy checks
  -> Authelia
  -> application
```

```text
metrics -> Prometheus -> Grafana
                    -> Alertmanager -> ntfy / Telegram

logs -> Promtail -> Loki -> Grafana
security telemetry -> Wazuh -> enrichment / response
```

## Notes

This is not a turnkey deployment repository.

It is a curated mirror of the parts that are worth sharing publicly:
- architecture
- ingress and access patterns
- monitoring and alerting layout
- security workflow examples
- Terraform/OpenTofu structure
- operator-facing documentation and scripts

What is intentionally left out:
- live secrets
- generated state
- exact runtime configs from the private environment
- private hostnames, IPs, and internal-only service wiring

## Live site

- GitHub Pages: https://asharahmed.github.io/homelab/
