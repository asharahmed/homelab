# Azure security posture (Microsoft Defender for Cloud)

Cloud Security Posture Management (CSPM) for the Azure footprint, enabled as
code and kept on the **free** tier under the Azure-for-Students $100 cap.

## What it gives you

- **Secure Score** — a prioritized posture score across every Azure resource
  (the Sentinel workspace, Logic App playbook, storage, the OIDC app, etc.).
- **Recommendations** — concrete hardening actions, ranked by impact.
- **Regulatory compliance dashboard** — posture mapped to frameworks:
  - **MCSB** (Microsoft Cloud Security Benchmark) — assigned automatically.
  - **CIS** Microsoft Azure Foundations Benchmark v2.0.0 — assigned here (audit-only).

## Cost safety (important)

Defender for Cloud has a free foundational tier and paid workload plans
(Defender for Servers/Storage/SQL/Containers/… and the premium Defender CSPM).
This lab runs **only the free foundational CSPM**. `deploy-defender-for-cloud.ps1`
enforces that with a **cost guardrail**: it forces every billable plan to the
`Free` tier on each run. `FoundationalCspm` and `Discovery` report tier
`Standard` — that means the free foundation is *enabled*, not billed; they're
left alone.

> **NIST SP 800-53 Rev. 5 is deliberately not assigned.** Its initiative
> bundles `deployIfNotExists` policies that need a managed identity and can
> deploy resources — a cost risk on a capped subscription. CIS (audit-only)
> plus MCSB is the zero-risk two-framework baseline.

## Files

| File | Purpose |
|------|---------|
| `deploy-defender-for-cloud.ps1` | Idempotent: register provider → force all paid plans Free → assign CIS. Run with `-WhatIf` to preview. |

## Usage

```powershell
./deploy-defender-for-cloud.ps1 -WhatIf   # preview
./deploy-defender-for-cloud.ps1           # apply
```

The first assessment scan populates Secure Score and the compliance dashboard
within ~30 min to a few hours. View in the portal:
**Microsoft Defender for Cloud → Secure Score** and **→ Regulatory compliance**.

## Notes

- Auth: Azure CLI signed in as an account with Owner/Security Admin on the
  subscription. `az role assignment`/`az policy assignment` hit a
  `MissingSubscription` quirk on the build host — the script uses `az rest`
  against ARM directly to avoid it.
