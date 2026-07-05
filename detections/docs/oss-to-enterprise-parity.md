# OSS → Enterprise coverage-parity matrix (WS E gate)

Decision record for retiring the self-hosted security stack (Wazuh, Shuffle,
Velociraptor) in favor of Microsoft Sentinel + Defender XDR + Intune. Nothing
gets decommissioned while its row shows an open gap.

Status legend: ✅ enterprise replacement live · 🕓 deployed, verification pending ·
⬜ open gap · ➖ intentionally not migrated (stays on-prem / out of SIEM scope)

## 1. Detection content (Wazuh custom rules → Sigma → Sentinel/Defender)

The 47 Wazuh custom rules were ported to Sigma first
([wazuh-to-sigma-mapping.md](wazuh-to-sigma-mapping.md)); Sigma is the
permanent source of truth. This table tracks where each detection now *runs*.

### Windows endpoint (10 Sigma rules)

| Detection | Enterprise home | Status |
|---|---|---|
| Office/browser spawns LOLBin (T1566) | Sentinel scheduled rule (Defender `Device*` tables) | ✅ deployed |
| Encoded/download PowerShell (T1059) | Sentinel scheduled rule | ✅ deployed |
| LOLBin network connection (T1071) | Sentinel scheduled rule | ✅ deployed |
| Executable dropped in user-writable path (T1105) | Sentinel scheduled rule | ✅ deployed |
| Registry autostart persistence (T1547) | Sentinel scheduled rule | ✅ deployed |
| LSASS credential access (T1003) | Defender custom detection (`detections/defender/`) | ✅ deployed |
| Known C2 named pipe (T1071) | Defender custom detection | ✅ deployed |
| Remote thread injection (T1055) | Defender custom detection | ✅ deployed |
| Unsigned DLL from user-writable path (T1055) | Defender custom detection (path heuristic — no signing columns in tenant schema) | ✅ deployed + **alert verified firing** on asharpc (2026-07-01 21:01 UTC) |
| DNS to suspicious TLD (T1071.004) | Defender custom detection (`DeviceNetworkEvents` port 53 — no `DeviceDnsEvents` in tenant) | ✅ deployed |

> **End-to-end verified (WS A, 2026-07-02):** MDE backend provisioned;
> asharpc telemetry live (569 `DeviceProcessEvents`/6h). Encoded-PowerShell
> execution captured in `DeviceProcessEvents`. The **"Unsigned DLL Loaded
> from User-Writable Path"** custom detection fired a real alert
> (`DetectionSource: Custom detection`, host asharpc, T1055) — proving the
> deploy → telemetry → detection → alert path.
>
> **Open (WS B linkage):** in this USOP tenant `AlertInfo` has no
> `IncidentId` column and the Graph `security/incidents` API returns empty
> for these alerts — Defender custom-detection alerts are **not** promoting
> to Sentinel incidents automatically. The SOAR playbook (triggers on
> Sentinel incident creation) was verified separately with a test incident;
> wiring Defender alerts → Sentinel incidents needs the Defender XDR
> incident-sync confirmed in-portal.

### Custom log sources (Caddy / Authelia / Docker / router — 10 Sigma rules)

| Detection group | Enterprise home | Status |
|---|---|---|
| Caddy probing/scanner/stuffing (4 rules) | Requires AMA custom logs + DCR into Sentinel (WS C.3) | ⬜ gated on ingest budget — Wazuh rules stay authoritative until C.3 or acceptance of the gap |
| Authelia brute-force (2 rules) | Same C.3 dependency | ⬜ |
| Docker privileged/exec (2 rules) | Same C.3 dependency | ⬜ |
| Router SSH brute-force/login (2 rules) | Same C.3 dependency | ⬜ |

**Retirement impact:** these 10 detections are the only Wazuh content without
a live enterprise home. Options at the gate: (a) fund WS C.3 (AMA + DCR,
respecting the 1 GB/day cap), or (b) accept documented loss of SIEM alerting
on these sources (CrowdSec still blocks at the edge; Loki keeps the logs).

### Health/availability rules (~17 Wazuh rules)

➖ Operational signals (backup status, OOM, router health, Docker lifecycle)
— already owned by Prometheus/Alertmanager. Not SIEM content; retire with
Wazuh without replacement.

## 2. Threat intelligence

| OSS capability | Enterprise replacement | Status |
|---|---|---|
| `custom-hashcheck` / AbuseIPDB / CTI scripts (Wazuh integrations) | Sentinel TI: MDTI feed + AlienVault OTX TAXII + abuse.ch ThreatFox upload pipeline | ✅ **3 feeds live** (2026-07-03): MDTI ~200k, OTX ~2.5k, abuse.ch ThreatFox ~450/day. Query `ThreatIntelIndicators` (current table) — legacy `ThreatIntelligenceIndicator` is deprecated/empty. Pulsedive was the only paywalled option; MDTI + OTX are free-tier. |

## 3. SOAR (Shuffle workflow `b69f09de` + alert-relay `/selfheal`)

| OSS capability | Enterprise replacement | Status |
|---|---|---|
| Wazuh L10+ → ntfy/Telegram fan-out (Shuffle) | Sentinel automation rule → `sentinel-notify-playbook` Logic App (comment + Telegram + ntfy) | ✅ verified end-to-end |
| Guarded container self-heal (alert-relay Layer 1/2) | **Stays on-prem by design** (autoheal + alert-relay). Optional cloud bridge = Hybrid Runbook Worker / Tailnet (B.2 follow-on) | ➖ deliberate hybrid split |

## 4. EDR / forensics (Velociraptor)

| OSS capability | Enterprise replacement | Status |
|---|---|---|
| Endpoint hunting (VQL) | Defender Advanced Hunting (KQL over `Device*`) | 🕓 pending MDE backend provisioning (WS A) |
| Live response / triage collection | Defender Live Response (P2) | 🕓 same dependency |
| Vulnerability surface | Defender Vulnerability Management (included in P2) | 🕓 same dependency |

## 5. Device management

| OSS capability | Enterprise replacement | Status |
|---|---|---|
| (none — manual host config) | Intune: compliance baseline + Win11 VM fleet member (`tools/intune-vm/`) | 🕓 VM built unattended; Entra join + policy deploy pending |

## Gate summary (go/no-go per service)

| Service | Can retire when |
|---|---|
| **Shuffle** (×4 containers) | Now — notification path fully replaced and verified. |
| **Velociraptor** | MDE device active + one Advanced Hunting query and one Live Response session demonstrated. |
| **Wazuh** (×3 containers) | Windows detections verified firing (WS A) **and** the custom-source decision made (fund C.3 or accept the gap). |

---

## Retirement executed — 2026-07-04

WS E complete. All three OSS stacks (Wazuh ×3, Shuffle ×4, Velociraptor)
stopped, removed from `docker-compose.yml` / `Caddyfile` / Prometheus /
alerting, and their data deleted after a full backup
(`C:\legacy-oss-final-backup\`). Build code preserved in `archive/legacy-oss/`.
Wazuh Windows agent uninstalled from AsharPC; router-side forwarder was
removed during the 4.9.0 firmware upgrade. Gate satisfied by: MDE fleet live
(ASHARPC + MacBook Pro, both Onboarded), Intune compliance enforced, router
syslog in Sentinel `Syslog` table, custom detection verified firing.

**Accepted gap:** 4 Caddy log rules (probing/scanner/credential-stuffing) —
mitigated by CrowdSec at the edge; future path = Caddy logs via the existing
Logs Ingestion DCE (`detections/sentinel/router-telemetry/` pattern).
