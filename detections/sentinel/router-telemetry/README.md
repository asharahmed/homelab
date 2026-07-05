# Router telemetry -> Microsoft Sentinel

Ships the GL-BE9300 router's syslog into Sentinel's **native `Syslog` table**
via the Azure Monitor **Logs Ingestion API** — no agent, no collector VM.
Replaces the retired Wazuh remote-syslog pipeline (router previously logged
to the Wazuh manager on 5140/udp).

## Architecture

```
GL-BE9300 (logd, udp) --> sentinel-syslog container :5141/udp (AsharPC)
                             |  parse RFC3164, batch 30s
                             v
                  DCE dce-homelab (Logs Ingestion API)
                             |  DCR dcr-router-syslog
                             |  Custom-RouterSyslog -> Microsoft-Syslog
                             v
                    law-homelab: Syslog table (Sentinel)
```

Landing in the native `Syslog` table (not a `_CL` custom table) means
built-in Sentinel Syslog parsers and analytics (e.g. SSH brute-force
detections against `dropbear`/`sshd`) apply without modification.

## Files

| File | Purpose |
|------|---------|
| `router-syslog.bicep` | DCE + DCR (stream `Custom-RouterSyslog` -> `Microsoft-Syslog`) + Monitoring Metrics Publisher grant to the ingest service principal |
| `router-detections.bicep` | Sentinel scheduled analytics rule over the `Syslog` table (SSH brute-force on Dropbear, T1110.001). Source Sigma: `rules/custom/router_ssh_bruteforce.yml` |
| `../../../tools/monitoring/sentinel-syslog/` | Forwarder container (stdlib-only Python, udp/5141, monitoring profile) |

## Detection

`router-detections.bicep` deploys **Router SSH Brute Force (Dropbear)** — fires
when one source IP accumulates >=5 failed SSH attempts in a 10-minute window.
Dropbear splits an attempt across log lines (the auth-outcome line has no IP;
the source IP is on `Exit before auth from <IP:port>`), so the query keys off
the IP-bearing failure lines. Host + IP entity mappings roll matches into
incidents. Verified firing against 14 synthetic failed logins (2026-07-04).

```powershell
az deployment group create -g rg-sentinel `
  --template-file router-detections.bicep --parameters workspaceName=law-homelab
```

## Deploy

```powershell
az deployment group create -g rg-sentinel `
  --template-file router-syslog.bicep `
  --parameters workspaceName=law-homelab ingestPrincipalId=<sp-object-id>
# put the two outputs in .env as SENTINEL_DCE_ENDPOINT / SENTINEL_ROUTER_DCR_ID
docker compose --profile monitoring up -d --build sentinel-syslog
# router: uci set system.@system[0].log_port='5141'; uci commit system; /etc/init.d/log restart
```

## Verify

```kusto
Syslog
| where HostName == "GL-BE9300"
| summarize count() by ProcessName, SeverityLevel
```

## Notes

- Auth: client-credentials as the detections app (`DEFENDER_APP_ID`), which
  holds **Monitoring Metrics Publisher** scoped to the DCR only.
- Cost: router syslog is a few MB/day (analytics tier); the workspace daily
  cap bounds any spike.
- OpenWrt `logd` supports a single remote target, so pointing it at 5141
  stops the (already retired) Wazuh feed.
