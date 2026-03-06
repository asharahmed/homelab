# Engineering Decisions

## 1. Docker Compose instead of Kubernetes

The environment runs on a single primary host and is heavily stateful. Docker Compose keeps deployment, recovery, and troubleshooting straightforward without introducing orchestration overhead that does not materially improve this setup.

## 2. Caddy as the single ingress layer

Caddy is used as the only public entry point. That keeps certificate management, routing, access policy, and request logging in one place instead of scattering them across individual applications.

## 3. Authelia for authentication and service protection

Authelia fits the reverse-proxy model of the environment well. The goal is not to build a full identity platform; the goal is to put consistent authentication and session policy in front of sensitive services.

## 4. Infisical to reduce secret sprawl

Long-lived secrets are not treated as normal application config. Infisical provides a central store for operational secrets, while local scripts handle export and render steps for the runtime environment.

## 5. OpenTofu / Terraform only for external control planes

Infrastructure as code is limited to the parts that benefit from it most: DNS, external dependencies, and infrastructure metadata. Local container lifecycle stays in Compose instead of being forced into Terraform.

## 6. Prometheus + Loki + Alertmanager as the operational baseline

Metrics, logs, and alerting are kept in one coherent monitoring model. The objective is to make failures visible and actionable, not simply collect data.

## 7. Wazuh and CrowdSec for layered security coverage

Wazuh covers endpoint and log-oriented detection. CrowdSec covers log-derived blocking decisions at ingress. They serve different purposes and are kept separate rather than collapsed into one tool.

## 8. Public mirror kept separate from the operational repo

The public repository is intentionally curated. It exists to document architecture, patterns, and operational decisions without exposing secrets, generated state, internal-only topology, or private runtime wiring.
