#Requires -Version 7
<#
.SYNOPSIS
    Deploy the Intune compliance policy from compliance-policy.json.

.DESCRIPTION
    Creates or updates the Windows 10/11 compliance policy via Microsoft
    Graph and assigns it to all devices. Idempotent: matches on displayName.

    Auth is app-only using the detections-deployer app registration. The app
    additionally needs the DeviceManagementConfiguration.ReadWrite.All
    application permission (admin consent required) - the script fails with
    403 until that grant exists.

    Required .env variables (same as detections/defender deployer):
        AZURE_TENANT_ID, DEFENDER_APP_ID, DEFENDER_APP_SECRET

.EXAMPLE
    ./deploy-intune-policies.ps1
#>
param(
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path "$here/../.."

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
$policiesUrl = 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies'

$policyFiles = @('compliance-policy.json', 'compliance-policy-macos.json')

foreach ($file in $policyFiles) {
    $policy = Get-Content "$here/$file" -Raw | ConvertFrom-Json

    # scheduledActionsForRule is mandatory on create: mark noncompliant immediately.
    $body = $policy | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
    $body['scheduledActionsForRule'] = @(
        @{
            ruleName = 'PasswordRequired'
            scheduledActionConfigurations = @(
                @{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = '' }
            )
        }
    )

    $existing = (Invoke-RestMethod -Uri "$policiesUrl`?`$filter=displayName eq '$($policy.displayName)'" -Headers $headers).value |
        Select-Object -First 1

    if ($WhatIf) {
        $verb = if ($existing) { 'UPDATE' } else { 'CREATE' }
        Write-Host "WHATIF $verb : $($policy.displayName)" -ForegroundColor Yellow
        continue
    }

    if ($existing) {
        # PATCH takes the policy body without scheduledActionsForRule
        Invoke-RestMethod -Uri "$policiesUrl/$($existing.id)" -Headers $headers -Method PATCH `
            -Body ($policy | ConvertTo-Json -Depth 5) | Out-Null
        $policyId = $existing.id
        Write-Host "Updated : $($policy.displayName)" -ForegroundColor Green
    } else {
        $created = Invoke-RestMethod -Uri $policiesUrl -Headers $headers -Method POST `
            -Body ($body | ConvertTo-Json -Depth 6)
        $policyId = $created.id
        Write-Host "Created : $($policy.displayName) (id=$policyId)" -ForegroundColor Green
    }

    # Assign to all devices
    $assignment = @{
        assignments = @(
            @{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
        )
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$policiesUrl/$policyId/assign" -Headers $headers -Method POST -Body $assignment | Out-Null
    Write-Host 'Assigned to all devices.' -ForegroundColor Green
}
