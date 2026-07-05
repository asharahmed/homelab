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

## 7. CrowdSec at the edge, Microsoft Defender XDR/Sentinel for detection

CrowdSec covers log-derived blocking decisions at ingress. Endpoint and cloud-native detection now runs on Microsoft Defender XDR and Sentinel instead of a self-hosted SIEM. They serve different purposes and are kept separate rather than collapsed into one tool.

## 8. Microsoft Sentinel over a self-hosted SIEM

A self-hosted SIEM was the original choice, but it meant maintaining rule syntax, correlation engines, and threat-intel ingestion that have no equivalent outside that one product. Sentinel, Defender XDR, and Intune are what a real security team is more likely to run, and centralizing on them keeps the environment closer to production tooling: the same KQL, the same custom detection format, the same compliance and posture surfaces. The self-hosted SIEM was decommissioned once analytics rules, custom detections, and threat-intel feeds covered its prior scope.

## 9. Detection-as-code with CI/CD instead of console-authored rules

Sigma is the source of truth for every detection; Sentinel analytics rules and Defender custom detections are compiled from it and deployed with Bicep. GitHub Actions runs Sigma validation, a rules-in-sync check, a Bicep build, and schema checks on every pull request, then deploys via OIDC on merge. Authoring rules by hand in the Sentinel or Defender console would leave no history, no review step, and no way to catch a rule that silently stopped matching.

## 10. Continuous purple-team validation instead of trusting a rule was written correctly

Writing a detection and reading it back is not the same as proving it fires. An isolated, MDE-onboarded detonation-range VM runs Atomic Red Team techniques, and a validation loop confirms via advanced hunting that the intended detection actually triggered, emitting an ATT&CK Navigator coverage layer per run. This is not theoretical: the first run caught two custom detections filtering on a field Defender leaves empty for those action types, so they would have never fired in production. That is the argument for validating detections continuously rather than once at write time.

## 11. Public mirror kept separate from the operational repo

The public repository is intentionally curated. It exists to document architecture, patterns, and operational decisions without exposing secrets, generated state, internal-only topology, or private runtime wiring.
