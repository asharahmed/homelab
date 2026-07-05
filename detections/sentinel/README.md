# Microsoft Sentinel deployment

Deploys the Sigma detection library into **Microsoft Sentinel** as scheduled
analytics rules — the "Deploy" step of the detection lifecycle, done as code.

Authoring stays vendor-agnostic in `../rules/`. This directory turns the Windows
rules into live Sentinel analytics rules via:

```
../rules/windows/*.yml   →  generate-rules.py  →  analytics-rules.json  →  main.bicep  →  Sentinel
        (Sigma)              (compile + wrap)        (params)             (ARM/Bicep)     (analytics rules)
```

## Files

| File | Purpose |
|---|---|
| `generate-rules.py` | Compiles each Windows rule to KQL (`microsoft_xdr` pipeline), reads its metadata, writes `analytics-rules.json`. Idempotent — the Sigma rule `id` becomes the Sentinel rule name. |
| `analytics-rules.json` | Generated parameter file (committed so the deployable artifact is reviewable). |
| `workspace.bicep` | Creates a Log Analytics workspace and onboards it to Sentinel. Run once, or skip if you already have one. |
| `main.bicep` | Deploys the analytics rules from `analytics-rules.json` to the workspace. |
| `budget.bicep` | Subscription-scoped cost guardrail (80%/100% actual + 100% forecast email alerts). Deploy **before** connecting any data source. |
| `deploy.ps1` | Wrapper: preflight `az` auth → (optional) regenerate → (optional) create workspace → deploy. |
| `threat-intel.bicep` | Threat intelligence data connectors: the MDTI emerging-threat feed **and** a generic TAXII 2.x feed defaulting to the free **AlienVault OTX** server. |
| `deploy-threat-intel.ps1` | Deploys `threat-intel.bicep`; switches the TAXII connector on when `OTX_API_KEY` is in `.env`. |
| `push-abusech-ti.ps1` | Direct ingestion pipeline: pulls abuse.ch ThreatFox IOCs (free JSON API) → STIX 2.1 → Sentinel Upload Indicators API. abuse.ch has no TAXII server, so this replaces a connector. Deterministic UUIDv5 ids (re-runs update, not duplicate). |

> **Three TI feeds are live** (verified 2026-07-03): **MDTI** (~200k indicators),
> **AlienVault OTX** (~2.5k, via the TAXII connector), and **abuse.ch ThreatFox**
> (~450/day, via `push-abusech-ti.ps1`).
>
> **CRITICAL — query the right table.** Indicators land in **`ThreatIntelIndicators`**
> (the current TI table). The legacy **`ThreatIntelligenceIndicator`** (singular) is
> **deprecated and stays empty** — querying it gives a false "0 indicators / feed
> broken" reading. (Pulsedive was the one feed that genuinely required a paid plan;
> MDTI and OTX both work on the free tier.) Verify with:
> `ThreatIntelIndicators | summarize count() by SourceSystem`.

> **MITRE technique format:** Sentinel's `techniques` field accepts **parent IDs
> only** (`T####`) — the live API rejects sub-technique IDs like `T1071.001`
> despite the ARM schema typing it as a free `string[]`. `generate-rules.py`
> therefore collapses sub-techniques to their parent; full sub-technique
> precision stays in the Sigma rules and the ATT&CK Navigator layer.

## Prerequisites

1. **Azure subscription** with Microsoft Sentinel. A Log Analytics workspace is
   ~pay-per-GB; a homelab's volume sits in the low tens of dollars/month.
2. **Azure CLI** logged in: `az login` then `az account set --subscription <id>`.
   First-time subscriptions must register the providers: `az provider register
   --namespace Microsoft.OperationalInsights` (and `Microsoft.OperationsManagement`,
   `Microsoft.SecurityInsights`). Set a budget first: `az deployment sub create
   -l <region> -f budget.bicep --parameters contactEmail=you@example.com`.
3. **Microsoft Defender XDR connector enabled** in Sentinel. These rules query
   the advanced-hunting `Device*` tables (`DeviceProcessEvents`,
   `DeviceNetworkEvents`, `DeviceFileEvents`, `DeviceRegistryEvents`), which
   Sentinel only has once the Defender XDR data connector is streaming them.
4. For regeneration: `pip install -r ../requirements.txt`.

## Deploy

```powershell
# Dry run first — shows exactly what would change.
./deploy.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab -WhatIf

# Stand up a new workspace + onboard Sentinel + deploy rules.
./deploy.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab -CreateWorkspace -Location canadacentral

# Deploy into an existing workspace, regenerating from Sigma first.
./deploy.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab -Regenerate
```

The deploy is declarative and idempotent: re-running updates rules in place
(same `id` → same resource), so this is safe to wire into CI/CD as a
continuous-deployment stage once you trust the pipeline.

## Coverage — what deploys, and what doesn't

`generate-rules.py` deploys **5 of the 10 Windows rules**. The other 5 use Sysmon
event categories the stock `microsoft_xdr` pipeline doesn't map to a Defender XDR
table, so they're skipped rather than shipped broken:

| Rule | Sysmon category | Why it's skipped |
|---|---|---|
| `lsass_credential_access` | `process_access` | No `Device*` table for handle-open events in advanced hunting. |
| `c2_named_pipe` | `pipe_created` | No advanced-hunting table for named-pipe creation. |
| `remote_thread_injection` | `create_remote_thread` | No advanced-hunting table for remote-thread creation. |
| `unsigned_dll_from_user_writable_path` | `image_load` | Not mapped by the stock pipeline. |
| `dns_query_suspicious_tld` | `dns_query` | Not mapped by the stock pipeline. |

This is a **data-model boundary, not a bug** in the automated pipeline. All five
have since been **recovered as Defender XDR Custom Detection Rules** — re-authored
by hand as native advanced-hunting KQL against `DeviceEvents` ActionTypes,
`DeviceImageLoadEvents`, and `DeviceNetworkEvents`, and deployed as code from
[`../defender/`](../defender/README.md) via the Graph API. The Sigma rules remain
the source of truth for detection intent; the porting caveats (tables and columns
the tenant schema doesn't expose) are documented there.

The custom-source rules (`../rules/custom/` — Caddy/Authelia/Docker/router) are
out of scope here: they target custom Sentinel tables that require their own
ingestion (AMA custom logs / Logstash / a custom connector), which is a separate
piece of work from this Defender-XDR-backed rollout.

## Bringing data to the rules

The deployed rules query Defender XDR `Device*` tables, which are empty until a
host's EDR telemetry streams in. [`defender-xdr-onboarding.md`](defender-xdr-onboarding.md)
is the step-by-step runbook: start the Defender for Endpoint trial, onboard a
host, and turn on event streaming into the workspace — noting which steps are
portal-only (the Defender XDR connector's raw-event streaming isn't in the stable
ARM schema).

## Verify after deploy

In the Sentinel portal: **Analytics → Active rules** — the rules appear with their
ATT&CK tactics/techniques. Run an [Atomic Red Team](../docs/atomic-red-team-coverage.md)
test for a deployed technique (e.g. `T1059.001`), then confirm the rule fires and
raises an incident with the host entity populated.
