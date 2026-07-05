# Defender XDR Custom Detection Rules

Custom detection rules for Microsoft Defender XDR, deployed as code via the
Microsoft Graph beta API. These recover the 5 Windows Sigma rules that the
`microsoft_xdr` Sigma pipeline could not convert automatically (no direct
table mapping) — each was re-authored by hand against the advanced-hunting
schema. The Sigma rules in `../rules/windows/` remain the source of truth
for detection intent.

## Rules

| Rule | Source Sigma rule | Table | Technique | Severity |
|------|-------------------|-------|-----------|----------|
| Credential Access Attempt Against LSASS | `lsass_credential_access.yml` | `DeviceEvents` (`OpenProcessApiCall`) | T1003 | High |
| Known C2 Framework Named Pipe Created | `c2_named_pipe.yml` | `DeviceEvents` (`NamedPipeEvent`) | T1071 | High |
| Remote Thread Created in Sensitive System Process | `remote_thread_injection.yml` | `DeviceEvents` (`CreateRemoteThreadApiCall`) | T1055 | High |
| Unsigned DLL Loaded from User-Writable Path | `unsigned_dll_from_user_writable_path.yml` | `DeviceImageLoadEvents` | T1055 | Medium |
| DNS Query to Suspicious Top-Level Domain | `dns_query_suspicious_tld.yml` | `DeviceNetworkEvents` | T1071 | Low |

### Porting caveats (tenant schema deviations)

- **`DeviceDnsEvents` is not available** in this tenant's advanced-hunting
  schema. The DNS TLD rule uses `DeviceNetworkEvents` filtered to
  `RemotePort == 53` + `RemoteUrl` instead.
- **`DeviceImageLoadEvents` does not expose signing status** (`IsSigned` /
  `Signer` fail semantic validation). The unsigned-DLL rule falls back to a
  path-based heuristic (user-writable directories, non-AV initiating process).
- `AccountName` is not present on `DeviceImageLoadEvents` /
  `DeviceNetworkEvents`; use `InitiatingProcessAccountName`.

## Files

| File | Purpose |
|------|---------|
| `custom-detections.json` | Rule manifest (query, schedule, severity, MITRE mapping) |
| `deploy-custom-detections.ps1` | Idempotent deployer (create/update by displayName) |

## Deployment

```powershell
./deploy-custom-detections.ps1          # deploy/update all rules
./deploy-custom-detections.ps1 -WhatIf  # preview
```

### Auth: why app-only (client credentials)

Delegated auth does not work against the custom-detections API in this
tenant: the subscription-owner account is an MSA guest (rejected by the
security API), and `secadmin` lacks Defender RBAC API scopes. Instead, a
dedicated app registration (`detections-deployer`) holds the
`CustomDetection.ReadWrite.All` **application** permission (admin-consented),
and the script authenticates with client credentials from `.env`:

```
AZURE_TENANT_ID=...
DEFENDER_APP_ID=...
DEFENDER_APP_SECRET=...
```

### API notes (Graph beta)

- Endpoint: `POST/PATCH https://graph.microsoft.com/beta/security/rules/detectionRules`
- The legacy `api.security.microsoft.com` endpoint returns 403 for all
  identities in this tenant — use Graph.
- Required body shape: `queryCondition.queryText`, `schedule.frequency`
  (ISO 8601 duration, e.g. `PT1H`), `detectionAction.alertTemplate`
  (with `title`, `severity`, and `category` **or** `tactics`), and
  `impactedAssets` for entity mapping.
- Newly reset app secrets take ~1–2 minutes to propagate before token
  requests succeed.

## Verification

Rules are visible in the Defender portal under
**Hunting → Custom detection rules** (security.microsoft.com), or via:

```powershell
GET https://graph.microsoft.com/beta/security/rules/detectionRules
```
