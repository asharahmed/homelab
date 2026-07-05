# Wazuh → Sigma porting map

Source: `tools/wazuh/wazuh_cluster/rules/local_rules.xml` (47 custom rules, all MITRE-tagged).
This tracks the migration of that content into vendor-agnostic Sigma.

## Status legend
- ✅ ported in this PoC batch
- ⬜ planned
- ➖ operational/health rule — not a security detection; lower priority to port (or keep in metrics stack)

## Endpoint / Windows (Sysmon)

| Wazuh ID | Detection | ATT&CK | Sigma file | Status |
|---|---|---|---|---|
| 100501 | Office/browser spawns LOLBin | T1566.001 | windows/office_browser_spawns_lolbin.yml | ✅ |
| 100502 | Encoded/download PowerShell | T1059.001 | windows/powershell_encoded_or_download.yml | ✅ |
| 100510 | LOLBin network connection | T1071.001 | windows/lolbin_network_connection.yml | ✅ |
| 100520 | Unsigned DLL from user-writable path | T1055.001 | windows/unsigned_dll_from_user_writable_path.yml | ✅ |
| 100530 | Remote thread injection (refined to sensitive targets) | T1055 | windows/remote_thread_injection.yml | ✅ |
| 100540 | LSASS credential access | T1003.001 | windows/lsass_credential_access.yml | ✅ |
| 100550 | Executable dropped in user-writable path | T1105 | windows/executable_dropped_in_user_writable_path.yml | ✅ |
| 100560 | Registry autostart persistence | T1547.001 | windows/registry_run_key_persistence.yml | ✅ |
| 100570 | Known C2 named pipe | T1071 | windows/c2_named_pipe.yml | ✅ |
| 100580 | DNS query to suspicious TLD | T1071.004 | windows/dns_query_suspicious_tld.yml | ✅ |

## Web / Auth / Containers (custom JSON sources — need homelab-custom pipeline)

| Wazuh ID | Detection | ATT&CK | Sigma file | Status |
|---|---|---|---|---|
| 100201 | Sensitive path probing (Caddy) | T1595.003 | custom/caddy_sensitive_path_probe.yml | ✅ |
| 100203 | 4xx scanner burst (correlation) | T1595 | custom/caddy_4xx_scanner_burst.yml | ✅ |
| 100205 | Authelia bypass-token header | T1078 | custom/caddy_bypass_token_header.yml | ✅ |
| 100206 | Web credential stuffing (correlation) | T1110 | custom/caddy_credential_stuffing.yml | ✅ |
| 100303 | Authelia brute force (correlation, dup of 100311) | T1110 | — | ➖ |
| 100310/100311 | Failed 1FA + brute force (correlation) | T1110.001 | custom/authelia_1fa_bruteforce.yml | ✅ |
| 100312/100313 | Failed TOTP + brute force (correlation) | T1110.001 | custom/authelia_totp_bruteforce.yml | ✅ |
| 100404 | Privileged container start | T1611 | custom/docker_privileged_container_start.yml | ✅ |
| 100405 | Container exec session | T1609 | custom/docker_container_exec.yml | ✅ |

## Threat-intel / enrichment

| Wazuh ID | Detection | ATT&CK | Status |
|---|---|---|---|
| 100101/100103 | CrowdSec ban / attack-wave | — | ⬜ (better modeled as a Sentinel TI / watchlist join) |
| 100902–100904 | Hash reputation tiers | T1204.002 | ⬜ (model via MISP → Sentinel TI connector) |
| 100800 | Netify DPI high-risk flow | T1071 | ⬜ |

## Network device (OpenWrt router / Dropbear)

| Wazuh ID | Detection | ATT&CK | Sigma file | Status |
|---|---|---|---|---|
| 100660/100661 | Router SSH failed login + brute force (correlation) | T1110.001 | custom/router_ssh_bruteforce.yml | ✅ |
| 100662 | Router SSH login success (audit) | T1078 | custom/router_ssh_login_success.yml | ✅ |

## Health / availability (not security detections)

Router/kernel (100650–100652, 100680–100694), Docker lifecycle (100401–100403, 100406),
backup (100750–100752), restic, OOM/watchdog — these are operational signals. ➖ Keep in the
metrics/alerting stack (Prometheus/Alertmanager) rather than porting to the SIEM detection library.

## Remaining — intentionally not 1:1 ported

All standalone behavioral detections are now ported. What's left should **not** be
re-encoded as literal Sigma rules, because doing so would just wrap another tool's
output rather than detect a behavior:

- **Threat-intel / enrichment** — `100101/100103` (CrowdSec ban decisions),
  `100902-100904` (hash reputation tiers), `100800` (Netify DPI verdict). These fire on
  the *output* of an enrichment integration. Model them as **MISP indicators joined into
  Sentinel via the Threat Intelligence connector** (roadmap Phase 6), not as ported rules.
- **Health / availability** — router/kernel, Docker lifecycle, backup, OOM/watchdog. These
  belong in the metrics/alerting stack (Prometheus/Alertmanager), not the detection library.

## Progress

20 rule files / 25 detection documents ported — 10 Windows endpoint + 15 custom-source
(including **5 `event_count` correlation rules**), spanning endpoint / auth / container /
web / network-device telemetry. All lint clean (0 errors, 0 issues). Every standalone
behavioral detection from the source ruleset is now in Sigma.
