<p align="center">
  <img src="logo.svg" width="220" alt="Ashar Homelab mark"/>
</p>

<h1 align="center">Homelab</h1>

<p align="center">
  Security-first self-hosted infrastructure on Docker Compose, built as an operational platform rather than a container collection.
</p>

<p align="center">
  <a href="https://asharahmed.github.io/homelab/"><strong>Interactive documentation</strong></a>
  ·
  <a href="https://github.com/asharahmed"><strong>GitHub profile</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/containers-25%2B-b99b63?style=flat-square&labelColor=161b24" alt="25+ containers"/>
  <img src="https://img.shields.io/badge/SIEM_rules-30K%2B-bd6467?style=flat-square&labelColor=161b24" alt="30K+ SIEM rules"/>
  <img src="https://img.shields.io/badge/alert_rules-30%2B-5f9f7a?style=flat-square&labelColor=161b24" alt="30+ alert rules"/>
  <img src="https://img.shields.io/badge/remote_access-Tailscale-6d87b5?style=flat-square&labelColor=161b24" alt="Tailscale remote access"/>
</p>

## What This Is

This repository is the public-facing documentation for a Windows 11 + WSL2 homelab that I use to run security telemetry, observability, identity, AI tooling, and core self-hosted services.

The goal is not “host a lot of apps.” The goal is to operate a small but serious infrastructure platform with:

- clear ingress and access boundaries
- layered detection and response
- repeatable configuration and deployment workflows
- real operational visibility across host, containers, network edge, and logs

## Why It Matters

Most homelab repos stop at screenshots and service lists. This one is intended to show engineering judgment:

- how services are exposed and protected
- how telemetry is collected and correlated
- how incident signal moves from logs to alerts to response
- how a Compose-based stack can still be run with discipline

This is the kind of system design, ops thinking, and security posture I care about in production environments too.

## System Overview

**Platform base**

- Windows 11 Pro
- Docker Desktop + WSL2
- NVIDIA GPU for transcoding and local inference
- Tailscale mesh for remote administration

**Ingress and identity**

- Caddy as reverse proxy and TLS termination layer
- Authelia for SSO, 2FA, and OIDC-backed access control
- Internal services reachable through `*.home.aahmed.ca`

**Security stack**

- CrowdSec for log-driven intrusion prevention
- Wazuh for SIEM/XDR and custom detection rules
- Velociraptor for endpoint investigation and threat hunting
- Suricata + netifyd at the router edge for network detection and classification
- custom CTI ingestion and IOC enrichment workflows

**Observability stack**

- Prometheus for metrics, rules, and alert evaluation
- Alertmanager for routing to ntfy and Telegram
- Grafana for dashboards across metrics and logs
- Loki + Promtail for centralized log search
- Uptime Kuma and Blackbox Exporter for synthetic checks

## Architecture Snapshot

```text
Internet
  -> Caddy
  -> CrowdSec
  -> Authelia
  -> Service
```

```text
Metrics sources -> Prometheus -> Grafana
                           -> Alertmanager -> ntfy / Telegram

Logs -> Promtail -> Loki -> Grafana
SIEM -> Wazuh -> alerting / enrichment / response
```

The public site includes the fuller diagrams and service breakdown:

- ingress flow
- monitoring and logging pipeline
- network topology
- automation and platform layout

## Representative Capabilities

### 1. Defense in depth

Requests are not sent directly to backend services. Access passes through reverse proxy, reputation/blocking, authentication, and service-specific policy.

### 2. Security telemetry that is actually usable

This stack combines endpoint telemetry, network alerts, Prometheus metrics, and log aggregation into one operational picture instead of leaving each tool siloed.

### 3. Detection engineering

The environment includes custom Wazuh rules mapped to MITRE ATT&CK techniques for behaviors like:

- suspicious child processes
- encoded PowerShell activity
- credential-access patterns
- injection-related behavior
- persistence and C2 indicators

### 4. Operator-grade observability

I treat dashboards and alerting as operating surfaces, not decoration. Metrics, probes, and logs are wired together so failures are visible quickly and routed to the right channels.

### 5. Compose, but with discipline

This is still a Docker Compose stack, but it is managed with the same concerns I would bring to a larger environment: secret handling, ingress boundaries, health validation, documentation, and repeatable change workflows.

## Public Scope

This repository is intentionally sanitized for public presentation.

It focuses on:

- architecture
- security controls
- observability design
- automation patterns
- operational decisions

It does **not** attempt to mirror every private implementation detail from the live environment.

## Repo Contents

- `index.html` — the public interactive documentation page
- `logo.svg` — custom project mark
- `.github/workflows/pages.yml` — GitHub Pages deployment workflow

## Live Site

**GitHub Pages:** https://asharahmed.github.io/homelab/

## Technology

`Docker Compose` `Windows 11` `WSL2` `Caddy` `Authelia` `Prometheus` `Grafana` `Loki` `CrowdSec` `Wazuh` `Velociraptor` `Suricata` `Tailscale` `Ollama`

---

<p align="center">
  Built as a real operating environment, documented as a public systems portfolio.
</p>
