# Attack Surface Reduction (ASR) rules — audit mode

`deploy-asr-audit.ps1` deploys the standard ASR rule set to Intune-managed
Windows devices in **audit mode**, as a Settings Catalog configuration policy
assigned to all devices.

## Why audit first

Audit mode logs what each ASR rule *would* block without breaking anything.
Review the telemetry in Defender advanced hunting before switching to block:

```kql
DeviceEvents
| where ActionType startswith "Asr" and ActionType endswith "Audited"
| summarize count() by ActionType, DeviceName
```

Once the audit telemetry is clean (no legitimate app is caught), flip the
noisy-but-safe rules to `block` by editing the policy in Intune or changing
the option value in the script and re-running.

## Rules (19, all → audit)

Includes: block executable content from email, Office child-process creation,
obfuscated-script execution, credential stealing from LSASS, process creation
from PSExec/WMI, untrusted USB execution, Office process injection, and the
rest of the Microsoft standard set.

## Deploy

```powershell
./deploy-asr-audit.ps1        # add -WhatIf to preview
```

Requires `DeviceManagementConfiguration.ReadWrite.All` on the
detections-deployer app (already granted).

## macOS EDR note

The MacBook is already onboarded to Defender for Endpoint (see
`macos-mde/`). The **Microsoft Intune connection** toggle
(security.microsoft.com → Settings → Endpoints → Advanced features) is a
portal-only step that additionally shares macOS device-risk signals into
Conditional Access and enables connector-based onboarding for future Macs.
It is not required for the current Mac's EDR protection, which is already live.
