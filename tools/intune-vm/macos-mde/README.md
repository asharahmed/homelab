# Microsoft Defender for Endpoint on macOS, via Intune (as code)

Deploys MDE to Intune-managed Macs the enterprise way: Intune pushes the
app and pre-approves every macOS security prompt via configuration
profiles, so onboarding is zero-touch on the device.

## Files

| File | Source / purpose |
|------|------------------|
| `sysext.mobileconfig` | Approve Defender system extensions (github.com/microsoft/mdatp-xplat) |
| `fulldisk.mobileconfig` | Full Disk Access (PPPC) for Defender |
| `netfilter.mobileconfig` | Network content-filter approval |
| `notif.mobileconfig` | Notification permissions |
| `background_services.mobileconfig` | Background service approval (Ventura+) |
| `accessibility.mobileconfig` | Accessibility (DLP features) |
| `bluetooth.mobileconfig` | Bluetooth access (device control) |
| `onboarding.mobileconfig` | **Gitignored.** Org onboarding blob - download from security.microsoft.com > Settings > Endpoints > Onboarding > macOS (deployment method: Mobile Device Management / Microsoft Intune) |
| `deploy-macos-mde.ps1` | Creates/updates all of the above as Intune custom profiles + the `macOSMicrosoftDefenderApp` mobile app (required), assigned to all devices. Idempotent. |

## Graph permissions (detections-deployer app)

- `DeviceManagementConfiguration.ReadWrite.All` - profiles
- `DeviceManagementApps.ReadWrite.All` - the app

## Deploy

```powershell
./deploy-macos-mde.ps1        # add -WhatIf to preview
```

## Verify

On the Mac after Intune check-in: `mdatp health` should show
`licensed: true` and `real_time_protection_enabled: true`. In
security.microsoft.com > Assets > Devices the Mac appears as onboarded;
its telemetry lands in Defender XDR advanced hunting and incidents sync
to Sentinel.
