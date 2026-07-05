#Requires -Version 7
<#
.SYNOPSIS
    Deploy the Sigma-derived detection rules into Microsoft Sentinel.

.DESCRIPTION
    Regenerates analytics-rules.json from the Sigma library (optional), then
    deploys the scheduled analytics rules to an existing Sentinel-onboarded
    Log Analytics workspace. Pass -CreateWorkspace to stand up the workspace
    and onboard Sentinel first.

    Requires: Azure CLI (az) logged in to the target subscription, and the
    Sigma toolchain (pip install -r ../requirements.txt) if using -Regenerate.

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab -WhatIf

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab -CreateWorkspace -Location canadacentral
#>
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $WorkspaceName,
    [string] $Location = 'canadacentral',
    [switch] $CreateWorkspace,
    [switch] $Regenerate,
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $here
try {
    # Preflight: az present and authenticated.
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI (az) not found. Install it and run `az login` first.'
    }
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) { throw 'Not logged in. Run `az login` (and `az account set --subscription <id>`).' }
    Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan

    if ($Regenerate) {
        Write-Host 'Regenerating analytics-rules.json from the Sigma library...' -ForegroundColor Yellow
        python generate-rules.py
    }
    if (-not (Test-Path './analytics-rules.json')) {
        throw 'analytics-rules.json not found. Run with -Regenerate or generate it first.'
    }

    if ($CreateWorkspace) {
        Write-Host "Creating workspace '$WorkspaceName' and onboarding Sentinel..." -ForegroundColor Yellow
        az deployment group create `
            --resource-group $ResourceGroup `
            --template-file ./workspace.bicep `
            --parameters workspaceName=$WorkspaceName location=$Location `
            --output table
    }

    $deployArgs = @(
        'deployment', 'group', 'create',
        '--resource-group', $ResourceGroup,
        '--template-file', './main.bicep',
        '--parameters', "workspaceName=$WorkspaceName", 'ruleSet=@analytics-rules.json',
        '--output', 'table'
    )
    if ($WhatIf) { $deployArgs += '--what-if' }

    $ruleCount = (Get-Content ./analytics-rules.json -Raw | ConvertFrom-Json).rules.Count
    Write-Host "Deploying $ruleCount analytics rule(s) to '$WorkspaceName'..." -ForegroundColor Yellow
    az @deployArgs

    Write-Host 'Done.' -ForegroundColor Green
}
finally {
    Pop-Location
}
