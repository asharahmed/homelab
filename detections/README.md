# Detection-as-Code

A version-controlled library of [Sigma](https://github.com/SigmaHQ/sigma) detection rules, linted and compiled to multiple SIEM query languages by a CI/CD pipeline. Detections are authored once in vendor-agnostic Sigma and converted to **Splunk SPL** and **Microsoft Defender XDR / Sentinel KQL** on every change.

This is the engineering discipline behind modern detection work: detections treated as code — written, reviewed, tested, and continuously deployed — rather than clicked into a console. (Per the 2025 Anvilogic/SANS *State of Detection Engineering* survey, 62% of teams version-control rules but only **42% have a CI/CD pipeline** — this repo is in that 42%.)

## Why Sigma

One rule format compiles to 30+ backends — Splunk, Microsoft Sentinel/Defender, Elastic, QRadar, Chronicle (YARA-L). Writing detections in Sigma demonstrates **multi-SIEM** capability and keeps detection logic portable across employers and platforms.

## Structure

```
detections/
├── rules/
│   ├── windows/        # Sysmon / Windows endpoint detections (convert natively)
│   └── custom/         # Custom-app log sources (Caddy, Authelia, Docker) — need pipeline
├── pipelines/          # pySigma processing pipelines (field mappings for custom sources)
├── scripts/            # Local lint + convert helpers (mirror CI)
├── docs/               # Wazuh→Sigma porting map, lifecycle notes
├── .github/workflows/  # CI: lint + convert on every push/PR
├── requirements.txt    # sigma-cli + backends
└── Makefile
```

## Detection engineering lifecycle

1. **Idea** — a threat behavior to detect, anchored to a MITRE ATT&CK technique.
2. **Author** — write a Sigma rule under `rules/`, tagged with the `attack.tXXXX` technique.
3. **Lint** — `sigma check` validates schema + field names (CI gate).
4. **Convert** — compile to SPL + KQL; review the generated queries (CI artifact).
5. **Test** — exercise with [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) for the mapped technique; confirm the detection fires.
6. **Review** — peer review via pull request (see `CONTRIBUTING.md`).
7. **Deploy** — push compiled queries into the SIEM as analytics rules.
8. **Tune** — track false positives; refine `falsepositives:` and selection logic.

## Provenance

These rules were ported from a working Wazuh SIEM ruleset (47 custom rules, all MITRE-tagged). See `docs/wazuh-to-sigma-mapping.md` for the full porting status. This repo is the engineering-forward presentation of that detection content.

## Usage

```bash
pip install -r requirements.txt

# Lint every rule
sigma check rules/

# Compile Windows rules to Splunk SPL
sigma convert -t splunk -p sysmon rules/windows/ -o build/windows-splunk.spl

# Compile Windows rules to Microsoft Defender XDR / Sentinel KQL
sigma convert -t kusto -p microsoft_xdr rules/windows/ -o build/windows-sentinel.kql
```

Or `make lint` / `make convert` / `make all`.

### SIEM target status

| Target | Pipeline | Status |
|---|---|---|
| Splunk SPL | `sysmon` | ✅ all Windows rules compile cleanly (verified) |
| Defender XDR / Sentinel KQL | `microsoft_xdr` | ⚠️ partial — see below |

The Defender XDR advanced-hunting schema doesn't expose every Sysmon event the
way raw Sysmon does. `process_creation`, `network_connection`, `registry_set`,
and `image_load` map to `DeviceProcessEvents` / `DeviceNetworkEvents` /
`DeviceRegistryEvents` / `DeviceImageLoadEvents`. But **`process_access`
(the LSASS-handle detection) and `pipe_created` (the C2 named-pipe detection)
have no direct Defender XDR table**, so those rules don't convert under the
`microsoft_xdr` pipeline. This is a genuine data-model gap, not a tooling bug:
in a real deployment those two would be authored as native Sentinel analytics
rules against the raw `Sysmon`/`SecurityEvent` tables (forwarded via AMA), or
kept on Splunk. The CI KQL step is therefore best-effort (`continue-on-error`).

## Validation — tested, not assumed

Each detection is tied to a runnable [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team)
test (or a concrete manual procedure where no atomic fits). See
[`docs/atomic-red-team-coverage.md`](docs/atomic-red-team-coverage.md) for the full matrix:
rule → ATT&CK technique → atomic test → `Invoke-AtomicTest` command → expected detection.

```powershell
# list the mapped tests
powershell -ExecutionPolicy Bypass -File scripts/run-atomics.ps1 -ListOnly
# run them (isolated lab only — executes real attack techniques)
powershell -ExecutionPolicy Bypass -File scripts/run-atomics.ps1
```

11 of 19 detections have a direct atomic; the rest (web/auth/router behaviors with no atomic)
have documented manual procedures. The loop: run atomic → confirm the compiled query fires →
record coverage against MITRE ATT&CK.

## Coverage map

[`navigator/homelab-coverage.json`](navigator/homelab-coverage.json) is a MITRE
ATT&CK Navigator layer generated from the rule tags — **17 techniques across 8
tactics**, colored by detection severity. Load it at
[mitre-attack.github.io/attack-navigator](https://mitre-attack.github.io/attack-navigator/)
(*Open Existing Layer → Upload from local*) for a one-page heatmap of what the
library detects. See [`navigator/README.md`](navigator/README.md).

## Deploying to Microsoft Sentinel

[`sentinel/`](sentinel/) turns the Windows rules into live **Sentinel scheduled
analytics rules** as code: `generate-rules.py` compiles each rule to KQL and emits
`analytics-rules.json`, which `main.bicep` deploys to a Sentinel workspace (and
`workspace.bicep` can stand the workspace up). One command — `deploy.ps1` — runs
the whole chain, idempotently (each Sigma rule `id` maps to a stable Sentinel
resource). See [`sentinel/README.md`](sentinel/README.md) for prerequisites and
the honest coverage boundary (5 of 10 Windows rules deploy against Defender XDR
`Device*` tables; the rest need raw Sysmon via AMA).

## Extracting to a standalone public repo

This directory is designed to be the **root of its own repository** (the `.github/workflows/` CI runs only from a repo root). To publish it as a portfolio artifact:

```bash
git subtree split --prefix=detections -b detections-only
# push the detections-only branch to a new public repo
```

> **Before publishing:** scrub any secrets from the parent repo's history that could be referenced. This `detections/` tree contains no credentials by design.
