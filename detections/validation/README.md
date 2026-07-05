# Continuous detection validation (purple team as code)

Closes the loop that `../docs/atomic-red-team-coverage.md` opens: instead of
running an atomic and *manually* eyeballing the SIEM, this **runs the technique
and automatically confirms the detection has visibility**, then publishes a
pass/fail record and a MITRE ATT&CK Navigator coverage layer.

## What it proves

For each deployed detection, a verification query asks advanced hunting: *did
the telemetry this rule keys on actually land in the window?* A match means the
technique is observable and the rule's data source is populated — the
purple-team "do we have visibility" signal. This catches silent detection decay
(a renamed table, a broken DCR, an EDR gap) before an incident does.

Telemetry-level (not alert-level) on purpose: it's deterministic within ingest
latency (~5-15 min), whereas scheduled custom detections only alert hourly.

## Files

| File | Purpose |
|------|---------|
| `validate-detections.ps1` | Rule->technique->atomic->verification map; runs each verification via Graph `runHuntingQuery`; writes results + Navigator layer. `-RunAtomics` executes the mapped atomics first (lab host only). |
| `results/latest.json` | Most recent run (pass/fail per detection). |
| `coverage-layer.json` | ATT&CK Navigator layer — import at mitre-attack.github.io/attack-navigator. |

## Run

```powershell
# Verify against existing telemetry (safe, schedulable)
./validate-detections.ps1

# Full purple-team pass: run atomics, wait for ingest, verify (ISOLATED lab host)
./validate-detections.ps1 -RunAtomics
```

Exit code is non-zero if any detection fails to validate — so CI or a scheduled
task can alert on coverage regression.

## Verification vs. exercise

- **PASS** = matching telemetry present in the lookback window.
- **FAIL** = no matching telemetry. Either the technique wasn't exercised
  recently, or the data source is broken. Run `-RunAtomics` (or a targeted
  atomic) to exercise it; if it still fails, the detection has a real visibility
  gap.

Some techniques (LSASS access, remote-thread injection, Office->LOLBin) require
the destructive atomics and an isolated host. Benign ones (suspicious-TLD DNS,
C2-named-pipe) can be triggered synthetically — see the coverage matrix.

## Scheduling

Run verify-only on a schedule (Task Scheduler / cron) to detect coverage drift;
run `-RunAtomics` on an isolated lab host during a dedicated purple-team window.
Commit `coverage-layer.json` so the coverage heatmap is versioned in Git.

## Detonation range (`detonate-in-vm.ps1`)

`Win11-AtomicLab` is a purpose-built isolated detonation range: a Hyper-V VM,
MDE-onboarded (telemetry flows to the same tenant the detections run in), on a
dedicated `AtomicNAT` internal switch (internet for MDE, no production-LAN
reachability), with Defender AV + Tamper Protection + LSA Protection disabled so
techniques execute to completion. `detonate-in-vm.ps1` drives it over PowerShell
Direct and detonates the technique behind every deployed detection using the
highest-fidelity lab-safe trigger (real mavinject injection, comsvcs LSASS dump,
connected C2 named pipes, certutil LOLBin fetch, etc.), then you run the
validation loop to confirm each fired:

```powershell
./detonate-in-vm.ps1                 # detonate all; add -Only rule1,rule2 to scope
# wait ~15 min for ingestion
./validate-detections.ps1 -LookbackMinutes 40
```

Range setup notes (one-time, per `sentinel-live-deployment` memory): static IP
`192.168.99.10` is re-applied by the script after each reboot; MDE onboarded via
the **Local Script** package (registry-blob transplant does NOT work on Windows);
AV/TP/PPL disabled for detonation; auto-logon enabled so `explorer.exe` (an
injection target) is present. This range **found two real detection bugs** on
first use - see `FINDINGS.md`.
