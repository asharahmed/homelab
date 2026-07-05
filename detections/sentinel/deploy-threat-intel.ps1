#Requires -Version 7
<#
.SYNOPSIS
    Deploy Sentinel threat intelligence data connectors (threat-intel.bicep).

.DESCRIPTION
    Deploys the Microsoft Defender Threat Intelligence free emerging-threat
    feed connector, and optionally a Pulsedive TAXII 2.1 connector when
    PULSEDIVE_TAXII_COLLECTION_ID is set in .env (free account required;
    the collection ID doubles as the password, username is 'taxii2').

    Indicators land in the ThreatIntelligenceIndicator table. First sync can
    take a few hours after enablement.

.EXAMPLE
    ./deploy-threat-intel.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab
#>
param(
    [string] $ResourceGroup = 'rg-sentinel',
    [string] $WorkspaceName = 'law-homelab',
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path "$here/../.."

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) { throw 'Not logged in. Run: az login --use-device-code' }
Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan

# Optional TAXII feed from .env. Default is AlienVault OTX (free): the
# username is your OTX API key, password is blank. OTX_API_KEY in .env
# switches the TAXII connector on.
$envFile = "$repoRoot/.env"
$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*([^#][^=]*)=(.*)$' } | ForEach-Object {
        $envVars[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
$otxKey = $envVars['OTX_API_KEY']
Write-Host "TAXII (AlienVault OTX) connector: $(if ($otxKey) { 'included' } else { 'skipped (no OTX_API_KEY in .env)' })" -ForegroundColor Yellow

# Sentinel's TAXII connector rejects a blank password ("Basic authentication
# requires both UserName and Password"), so pass the OTX key in both fields.
# OTX authenticates on the username (API key) and ignores the password.
$deployArgs = @(
    'deployment', 'group', 'create',
    '--resource-group', $ResourceGroup,
    '--template-file', "$here/threat-intel.bicep",
    '--parameters', "workspaceName=$WorkspaceName", "taxiiUserName=$otxKey", "taxiiPassword=$otxKey",
    '--name', 'threat-intel-connectors',
    '--output', 'table'
)
if ($WhatIf) { $deployArgs += '--what-if' }

az @deployArgs
Write-Host 'Done. Verify: ThreatIntelligenceIndicator | summarize count() by SourceSystem' -ForegroundColor Green
