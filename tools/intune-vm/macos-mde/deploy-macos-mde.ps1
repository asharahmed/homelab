#Requires -Version 7
<#
.SYNOPSIS
    Deploy Microsoft Defender for Endpoint to macOS via Intune, as code.

.DESCRIPTION
    Creates/updates:
      1. One Intune custom configuration profile per official Microsoft
         .mobileconfig in this directory (system extension, Full Disk Access,
         network filter, notifications, background services, accessibility,
         bluetooth) - source: github.com/microsoft/mdatp-xplat.
      2. The MDE onboarding profile, if onboarding.mobileconfig exists here
         (download from security.microsoft.com > Settings > Endpoints >
         Onboarding > macOS > deployment method "Mobile Device Management /
         Microsoft Intune"; gitignored - contains the org onboarding blob).
      3. The Microsoft Defender app itself (macOSMicrosoftDefenderApp).

    All idempotent (matched on displayName) and assigned to all devices.

    Graph application permissions required on the detections-deployer app:
      - DeviceManagementConfiguration.ReadWrite.All  (profiles)
      - DeviceManagementApps.ReadWrite.All           (the app; script skips
        app deployment with a warning if this grant is missing)

.EXAMPLE
    ./deploy-macos-mde.ps1
#>
param(
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path "$here/../../.."

$envVars = @{}
Get-Content "$repoRoot/.env" | Where-Object { $_ -match '^\s*([^#][^=]*)=(.*)$' } | ForEach-Object {
    $envVars[$Matches[1].Trim()] = $Matches[2].Trim()
}
foreach ($required in 'AZURE_TENANT_ID', 'DEFENDER_APP_ID', 'DEFENDER_APP_SECRET') {
    if (-not $envVars[$required]) { throw "Missing $required in .env" }
}

$formBody = 'grant_type=client_credentials' +
    "&client_id=$($envVars['DEFENDER_APP_ID'])" +
    "&client_secret=$([uri]::EscapeDataString($envVars['DEFENDER_APP_SECRET']))" +
    '&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default'
$token = (Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$($envVars['AZURE_TENANT_ID'])/oauth2/v2.0/token" `
    -Body $formBody -ContentType 'application/x-www-form-urlencoded').access_token
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$configsUrl = 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations'
$allDevices = @{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }

# ---- 1 + 2: configuration profiles -------------------------------------
$profiles = Get-ChildItem "$here/*.mobileconfig" | Sort-Object Name
if (-not $profiles) { throw "No .mobileconfig files found in $here" }

foreach ($file in $profiles) {
    $display = "MDE macOS - $($file.BaseName)"
    $payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
    $body = @{
        '@odata.type'  = '#microsoft.graph.macOSCustomConfiguration'
        displayName    = $display
        description    = 'Microsoft Defender for Endpoint prerequisite profile (microsoft/mdatp-xplat). Deployed as code.'
        payloadName    = $file.BaseName
        payloadFileName = $file.Name
        payload        = $payload
    }

    $existing = (Invoke-RestMethod -Uri "$configsUrl`?`$filter=displayName eq '$display'" -Headers $headers).value |
        Select-Object -First 1

    if ($WhatIf) {
        $verb = if ($existing) { 'UPDATE' } else { 'CREATE' }
        Write-Host "WHATIF $verb : $display" -ForegroundColor Yellow
        continue
    }

    if ($existing) {
        Invoke-RestMethod -Uri "$configsUrl/$($existing.id)" -Headers $headers -Method PATCH `
            -Body ($body | ConvertTo-Json -Depth 4) | Out-Null
        $profileId = $existing.id
        Write-Host "Updated : $display" -ForegroundColor Green
    } else {
        $created = Invoke-RestMethod -Uri $configsUrl -Headers $headers -Method POST `
            -Body ($body | ConvertTo-Json -Depth 4)
        $profileId = $created.id
        Write-Host "Created : $display" -ForegroundColor Green
    }

    $assignBody = @{ assignments = @($allDevices) } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$configsUrl/$profileId/assign" -Headers $headers -Method POST -Body $assignBody | Out-Null
}

if (-not (Test-Path "$here/onboarding.mobileconfig")) {
    Write-Host "NOTE: onboarding.mobileconfig not found - download the macOS MDM onboarding package" -ForegroundColor Yellow
    Write-Host "      from security.microsoft.com > Settings > Endpoints > Onboarding > macOS" -ForegroundColor Yellow
    Write-Host "      (deployment method: Mobile Device Management / Microsoft Intune)," -ForegroundColor Yellow
    Write-Host "      save it here as onboarding.mobileconfig, and re-run." -ForegroundColor Yellow
}

# ---- 3: the Defender app ------------------------------------------------
$appsUrl = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
$appDisplay = 'Microsoft Defender for Endpoint (macOS)'
try {
    $existingApp = (Invoke-RestMethod -Headers $headers `
        -Uri "$appsUrl`?`$filter=isof('microsoft.graph.macOSMicrosoftDefenderApp')").value |
        Select-Object -First 1

    if ($WhatIf) {
        $verb = if ($existingApp) { 'SKIP (exists)' } else { 'CREATE' }
        Write-Host "WHATIF $verb : $appDisplay" -ForegroundColor Yellow
        return
    }

    if (-not $existingApp) {
        $appBody = @{
            '@odata.type' = '#microsoft.graph.macOSMicrosoftDefenderApp'
            displayName   = $appDisplay
            description   = 'Microsoft Defender for Endpoint, deployed as code.'
            publisher     = 'Microsoft'
        } | ConvertTo-Json
        $existingApp = Invoke-RestMethod -Uri $appsUrl -Headers $headers -Method POST -Body $appBody
        Write-Host "Created : $appDisplay" -ForegroundColor Green
    } else {
        Write-Host "Exists  : $appDisplay" -ForegroundColor Green
    }

    $appAssign = @{
        mobileAppAssignments = @(
            @{
                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                intent        = 'required'
                target        = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
            }
        )
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$appsUrl/$($existingApp.id)/assign" -Headers $headers -Method POST -Body $appAssign | Out-Null
    Write-Host 'App assigned (required) to all devices.' -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 403) {
        Write-Host 'App deployment SKIPPED: grant DeviceManagementApps.ReadWrite.All (78145de6-330d-4800-a6ce-494ff2d33d07) + admin consent, then re-run.' -ForegroundColor Yellow
    } else { throw }
}
