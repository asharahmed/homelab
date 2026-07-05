# Intune device management (WS D) — Windows + macOS

Stands up the throwaway Windows 11 endpoint that, together with the Docker
host, forms the 2-device Intune/Defender managed "fleet". The VM is built
fully unattended on local Hyper-V; only the Entra join is interactive
(MFA cannot be scripted).

## Files

| File | Purpose |
|------|---------|
| `new-intune-vm.ps1` | Creates a Gen2 VM (Secure Boot + vTPM, Win11-compliant), builds an answer-file ISO, starts the unattended install, auto-answers the DVD boot prompt via WMI. |
| `autounattend.xml` | Answer file — wipes disk 0, installs Enterprise eval, creates `labadmin` local admin, skips all OOBE screens. Password templated from `.env` `VM_LOCAL_PASSWORD`. |
| `compliance-policy.json` | Intune compliance baseline (Windows): BitLocker, Secure Boot, TPM, Defender AV active + current signatures, firewall, alphanumeric password, Win11 22H2+ minimum. |
| `compliance-policy-macos.json` | Intune compliance baseline (macOS): FileVault, firewall, SIP, Gatekeeper (App Store + identified developers), alphanumeric password, macOS 13+ minimum. |
| `deploy-intune-policies.ps1` | Creates/updates both compliance policies via Graph (app-only) and assigns them to all devices. |

## Workflow

```powershell
# 1. Download the eval ISO (~6.8 GB) to D:\ISOs\win11-enterprise-eval.iso
#    https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise

# 2. Build + start the VM (elevated shell)
./new-intune-vm.ps1 -IsoPath D:\ISOs\win11-enterprise-eval.iso

# 3. Wait ~15-30 min for install; VM auto-logs-on as labadmin

# 4. Entra join + Intune enrollment (interactive, on the VM console):
#    Settings > Accounts > Access work or school > Connect
#    Sign in as secadmin@asharasharahmed.onmicrosoft.com (MFA)
#    MDM auto-enrollment picks the device up in Intune.

# 5. Deploy the compliance policy (needs DeviceManagementConfiguration.ReadWrite.All
#    application permission on the detections-deployer app; see below)
./deploy-intune-policies.ps1
```

## macOS enrollment workflow

```text
1. APNs certificate (one-time, portal — needs an Apple ID you will keep):
   intune.microsoft.com (as secadmin) > Devices > macOS > macOS enrollment
   > Apple MDM Push certificate: grant consent, download the CSR, create the
   push cert at identity.apple.com, upload the .pem back. Renew yearly with
   the SAME Apple ID.

2. Enroll the Mac (on the device):
   Install Company Portal (https://aka.ms/EnrollMyMac), sign in with the
   Entra account, approve the management profile in System Settings >
   Privacy & Security > Profiles. Device becomes Entra-registered +
   Intune-enrolled.

3. Deploy compliance baselines (both platforms):
   ./deploy-intune-policies.ps1

4. MDE on the Mac: Intune > Endpoint security > EDR > macOS onboarding
   policy (uses the Defender-Intune connection below) + the Microsoft
   Defender app deployed from Intune. Its telemetry lands in Defender XDR
   and incidents sync to Sentinel. Replaces the retired Wazuh
   files/enrol/macos-enrol.command path.
```

## Portal-only follow-ups

- **MDE onboarding via Intune**: Defender portal → Settings → Endpoints →
  Advanced features → *Microsoft Intune connection* ON, then Intune →
  Endpoint security → Endpoint detection and response → create the
  "Onboard devices to Defender" policy. Ties WS A and WS D together.
- **ASR rules**: Intune → Endpoint security → Attack surface reduction —
  start the standard-protection set in audit mode.

## Auth note

`deploy-intune-policies.ps1` reuses the `detections-deployer` app
registration (`DEFENDER_APP_ID` in `.env`). Intune Graph calls additionally
require the `DeviceManagementConfiguration.ReadWrite.All` **application**
permission with admin consent; the script returns 403 until that grant is
added. `DeviceManagementServiceConfig.Read.All` (APNs/enrollment status)
and `DeviceManagementManagedDevices.Read.All` (device inventory checks)
round out the read-side:

```powershell
az ad app permission add --id $env:DEFENDER_APP_ID `
  --api 00000003-0000-0000-c000-000000000000 `
  --api-permissions 9241abd9-d0e6-425a-bd4f-47ba86e767a4=Role `
                    06a5fe6d-c49d-46a7-b082-56b1b14103c7=Role `
                    2f51be20-0bb4-4fed-bf7b-db946066c75e=Role
az ad app permission admin-consent --id $env:DEFENDER_APP_ID
```
