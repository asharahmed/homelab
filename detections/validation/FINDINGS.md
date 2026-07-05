# Validation findings

Real coverage gaps surfaced by the validation loop — the point of running it.

## 2026-07-04 — DeviceNetworkEvents nearly empty on AsharPC

`DeviceNetworkEvents` returns ~0 rows (0 in 2h, 1 in 24h) on the tenant.
It is the data source for two deployed detections:

- `dns_query_suspicious_tld` (T1071.004) — `DeviceNetworkEvents | where RemotePort==53 ...`
- `lolbin_network_connection` (T1105) — `DeviceNetworkEvents | where InitiatingProcessFileName in~ (...)`

Neither can be reliably validated because the table is unpopulated. No
`DeviceEvents` `DnsQueryResponse` rows either. Synthetic triggers (nslookup to
.ru/.xyz, PowerShell resolves) produced nothing.

**Interpretation:** the network-event sensor component is not reporting on this
endpoint (possible: MDE trial limitation, network real-time inspection disabled,
or the DNS Client service `svchost` path which the DNS rule deliberately
excludes). This is a genuine visibility gap, not a rule-logic bug.

**Next steps (not yet done):**
- Confirm on the isolated VM whether `DeviceNetworkEvents` populates there (rules
  out a host-specific vs tenant-wide cause).
- If tenant-wide: the two network rules should move to an alternate source
  (e.g. router DNS logs already in the Sentinel `Syslog` table via
  router-telemetry, or Defender network-protection events) rather than
  `DeviceNetworkEvents`.
- Named-pipe (`c2_named_pipe`): transient synthetic pipes were not captured;
  needs a connected pipe or the real C2 tooling to validate.

## 2026-07-04 — TWO detections keyed on the wrong field (both fixed)

Purple-team validation in the isolated VM (Win11-AtomicLab, MDE-onboarded)
caught two deployed custom detections that would have **silently never fired**:

| Rule | Bug | Fix |
|------|-----|-----|
| `remote_thread_injection` (T1055) | Filtered `AdditionalFields.TargetProcessName`, which is **empty** for `CreateRemoteThreadApiCall`. Target is in `FileName`. | Filter `FileName` as target, `InitiatingProcessFileName` as injector-exclusion. Verified vs a mavinject-into-explorer event. |
| `lsass_credential_access` (T1003.001) | Filtered `AdditionalFields.TargetProcessName`, which is **absent** for `OpenProcessApiCall` (AdditionalFields holds only `{DesiredAccess}`). Target is in `FileName`. | Filter `FileName` as target, `InitiatingProcessFileName` as accessor-exclusion; surface `DesiredAccess` (0x1410 = cred-dump mask). Verified vs a comsvcs LSASS dump. |

**Root cause / lesson:** the MDE `Device*` "ApiCall" ActionTypes
(`OpenProcessApiCall`, `CreateRemoteThreadApiCall`) put the **target process in
`FileName`** and the **actor in `InitiatingProcessFileName`** — they do NOT
populate `AdditionalFields.TargetProcessName` (that field belongs to other
schemas). Rules hand-authored assuming a `TargetProcessName` field compile fine
and deploy clean but never match. Only running the technique and checking the
telemetry surfaces it. Both rules redeployed to Defender + validation loop
verification queries corrected.

All three destructive detections validated in the VM after the fixes:
office->LOLBin, remote-thread injection, LSASS credential access.
