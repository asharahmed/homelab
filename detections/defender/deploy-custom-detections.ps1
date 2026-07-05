#Requires -Version 7
<#
.SYNOPSIS
    Deploy Defender XDR Custom Detection Rules from custom-detections.json.

.DESCRIPTION
    Reads custom-detections.json and creates or updates each rule via the
    Microsoft Graph beta API (/beta/security/rules/detectionRules).
    Idempotent: matches on displayName and PATCHes existing rules rather
    than duplicating them.

    Auth is app-only (client credentials) using the detections-deployer app
    registration, which holds the CustomDetection.ReadWrite.All application
    permission. Delegated tokens do not work here: the guest account is an
    MSA (rejected by the security API) and secadmin lacks Defender RBAC
    API scopes.

    Required .env variables:
        AZURE_TENANT_ID       - Entra tenant ID
        DEFENDER_APP_ID       - app registration client ID
        DEFENDER_APP_SECRET   - app registration client secret

.EXAMPLE
    ./deploy-custom-detections.ps1
    ./deploy-custom-detections.ps1 -WhatIf
#>
param(
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path "$here/../.."

# Load creds from .env
$envVars = @{}
Get-Content "$repoRoot/.env" | Where-Object { $_ -match '^\s*([^#][^=]*)=(.*)$' } | ForEach-Object {
    $envVars[$Matches[1].Trim()] = $Matches[2].Trim()
}
foreach ($required in 'AZURE_TENANT_ID', 'DEFENDER_APP_ID', 'DEFENDER_APP_SECRET') {
    if (-not $envVars[$required]) { throw "Missing $required in .env" }
}

$tenantId = $envVars['AZURE_TENANT_ID']
$appId    = $envVars['DEFENDER_APP_ID']
$secret   = $envVars['DEFENDER_APP_SECRET']

Write-Host "Requesting Graph token (app $appId)..." -ForegroundColor Cyan
$formBody = 'grant_type=client_credentials' +
    "&client_id=$appId" +
    "&client_secret=$([uri]::EscapeDataString($secret))" +
    '&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default'
$token = (Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -Body $formBody -ContentType 'application/x-www-form-urlencoded').access_token

$headers = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}
$rulesUrl = 'https://graph.microsoft.com/beta/security/rules/detectionRules'

$manifest = Get-Content "$here/custom-detections.json" | ConvertFrom-Json

# Fetch existing rules once (for idempotent upsert)
$existing = (Invoke-RestMethod -Uri $rulesUrl -Headers $headers).value

foreach ($rule in $manifest.rules) {
    $body = @{
        displayName     = $rule.displayName
        description     = $rule.description
        status          = 'enabled'
        queryCondition  = @{ queryText = $rule.query }
        schedule        = @{ frequency = $rule.queryFrequency }
        detectionAction = @{
            alertTemplate = @{
                title           = $rule.displayName
                description     = $rule.description
                severity        = $rule.severity
                category        = $rule.category
                mitreTechniques = $rule.mitreTechniques
                impactedAssets  = @(@{
                    '@odata.type' = '#microsoft.graph.security.impactedDeviceAsset'
                    identifier    = 'deviceName'
                })
            }
        }
    } | ConvertTo-Json -Depth 8

    $match = $existing | Where-Object { $_.displayName -eq $rule.displayName } | Select-Object -First 1

    if ($WhatIf) {
        $verb = if ($match) { 'UPDATE' } else { 'CREATE' }
        Write-Host "WHATIF $verb : $($rule.displayName)" -ForegroundColor Yellow
        continue
    }

    if ($match) {
        Invoke-RestMethod -Uri "$rulesUrl/$($match.id)" -Headers $headers -Method PATCH -Body $body | Out-Null
        Write-Host "Updated : $($rule.displayName)" -ForegroundColor Green
    } else {
        $created = Invoke-RestMethod -Uri $rulesUrl -Headers $headers -Method POST -Body $body
        Write-Host "Created : $($rule.displayName) (id=$($created.id))" -ForegroundColor Green
    }
}
Write-Host 'Done.' -ForegroundColor Green
