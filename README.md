<p align="center">
  <img src="logo.svg" width="220" alt="Homelab Logo"/>
</p>

<h1 align="center">homelab</h1>

<p align="center">
  <strong>Self-hosted infrastructure platform — security, observability, and automation on Docker Compose.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/containers-25%2B-d19a66?style=flat-square&labelColor=141414" alt="25+ Containers"/>
  <img src="https://img.shields.io/badge/SIEM_rules-30K%2B-ff6369?style=flat-square&labelColor=141414" alt="30K+ SIEM Rules"/>
  <img src="https://img.shields.io/badge/alert_rules-30%2B-30d158?style=flat-square&labelColor=141414" alt="30+ Alert Rules"/>
  <img src="https://img.shields.io/badge/security_layers-8-bf5af2?style=flat-square&labelColor=141414" alt="8 Security Layers"/>
</p>

---

## Overview

25+ containers orchestrated through Docker Compose on WSL2, secured behind Authelia SSO, CrowdSec IPS, and Wazuh SIEM with live CTI feeds. Network-layer detection via Suricata IDS and netifyd DPI. Internal apps use `*.home.aahmed.ca` with Cloudflare DNS-01 certificates.

**[View the interactive documentation →](https://asharahmed.github.io/homelab/)**

---

## Architecture

Every inbound request passes through five layers before reaching a backend service:

```
Internet → Caddy (TLS) → CrowdSec (IPS) → Authelia (SSO/2FA) → Service
```

All services are bound to `127.0.0.1` and only reachable through the Caddy reverse proxy on Docker's `proxy_net` overlay.

## Security Stack

| Layer | Tool | Role |
|-------|------|------|
| Reverse Proxy | **Caddy** | TLS termination, CrowdSec bouncer, Cloudflare DNS-01 |
| Intrusion Prevention | **CrowdSec** | Crowd-sourced IP reputation, LAPI + bouncer |
| Authentication | **Authelia** | SSO gateway, passkey/TOTP 2FA, OIDC provider |
| SIEM / XDR | **Wazuh** | 30K+ rules, Sysmon integration, active response |
| Endpoint Detection | **Velociraptor** | Live forensics, artifact collection, threat hunting |
| Network IDS | **Suricata** | ET Open ruleset on GL-BE9300 router |
| DPI | **netifyd** | Application-layer traffic classification |
| Threat Intel | **Custom CTI feeds** | Daily IOC updates — IPs, domains, hashes |

### Sysmon Detection Coverage

Custom Wazuh rules mapped to MITRE ATT&CK:

- Suspicious child processes from Office/Browser — `T1566.001`
- Encoded/download commands — `T1059.001`
- LSASS credential access — `T1003.001`
- Remote thread injection — `T1055`
- Registry persistence & C2 named pipes

### Active Response

Automated blocking via `netsh` route-null with 1-hour timeout on high-confidence detections (credential access, injection, C2 beacons).

## Observability

```
Sources → Prometheus → Grafana (dashboards)
                    → Alertmanager → ntfy / Telegram
Logs   → Promtail  → Loki → Grafana (log search)
SIEM   → Wazuh     → Shuffle SOAR → Telegram
```

- **Prometheus**: Scrapes 15+ exporters (cAdvisor, windows-exporter, Blackbox probes, Exportarr, SNMP)
- **Grafana**: Unified dashboards with Prometheus + Loki datasources
- **Alertmanager**: Routes to ntfy (push notifications) and Telegram
- **Loki + Promtail**: Centralized log aggregation, 30-day retention
- **Blackbox Exporter**: 8 probe modules — TCP, DNS, TLS cert, ICMP, HTTP
- **Uptime Kuma**: External availability monitoring
- **Helix**: Custom aggregation dashboard for Prometheus, Alertmanager, Loki, Wazuh, CrowdSec APIs

## Networking

| Network | Purpose |
|---------|---------|
| `proxy_net` (172.30.0.0/24) | All services behind Caddy |
| Tailscale mesh (100.x.x.x) | Remote access overlay with split DNS |
| WireGuard VPN | Privacy-sensitive service isolation |
| CoreDNS | Authoritative DNS for `home.aahmed.ca` zone |

## Services

| Category | Services |
|----------|----------|
| Media | Plex, Sonarr, Radarr, Readarr, Bazarr, Tautulli, Overseerr, Maintainerr |
| AI / ML | Ollama + Open WebUI (GPU-accelerated local LLM) |
| Dashboards | Homarr, Grafana, Wazuh Dashboard |
| Processing | FileFlows (GPU transcoding) |
| Identity | Authelia (SSO + OIDC) |
| Utilities | Recyclarr, Watchtower |

## Automation

| Type | Scripts |
|------|---------|
| PowerShell | `validate-stack.ps1`, `prepare-monitoring.ps1`, `harden-rdp.ps1`, `cf-update-dns.ps1`, `vm-control.ps1` |
| Python | `update_cti_feeds.py`, `ioc_collector.py`, `threat_hunt_report.py`, `telegram-bot/app.py` |
| Scheduled | Watchtower (daily 4AM), CTI feeds (daily 3AM UTC), IOC collector (every 15min), Threat hunt report (daily 7AM UTC) |

## Infrastructure

| | |
|---|---|
| **OS** | Windows 11 Pro, Docker Desktop + WSL2 |
| **GPU** | NVIDIA — transcoding & LLM inference |
| **Remote** | Tailscale mesh + RDP |
| **Config** | Environment-driven, conventional commits |

## Tech Stack

`Docker` `WSL2` `Caddy` `Prometheus` `Grafana` `Loki` `Authelia` `CrowdSec` `Wazuh` `Suricata` `Velociraptor` `Tailscale` `Shuffle SOAR` `Ollama` `Plex`

---

<p align="center">
  <sub>Self-hosted on Windows 11 · Docker Desktop · WSL2</sub>
</p>
