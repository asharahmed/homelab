#Requires -Version 7
<#
.SYNOPSIS
    Deploy the Sentinel notification playbook and its automation rule.

.DESCRIPTION
    Reads Telegram and ntfy secrets from the repo .env file, deploys
    notify-playbook.bicep, then wires it to Sentinel via automation-rule.bicep.

    Requires: az CLI logged in as ashar@asharahmed.com (subscription Owner).

.EXAMPLE
    ./deploy-playbooks.ps1 -ResourceGroup rg-sentinel -WorkspaceName law-homelab
#>
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $WorkspaceName,
    [string] $Location = 'canadacentral',
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

function Get-DotEnvValue([string]$Key) {
    $envFile = Join-Path $here '..\..\..\\.env'
    $m = Select-String -Path $envFile -Pattern "^${Key}=(.+)$" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    throw ".env missing key: $Key"
}

$env:PATH = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) { throw 'Not logged in. Run: az login --use-device-code' }
Write-Host "Subscription : $($account.name) ($($account.id))" -ForegroundColor Cyan

$telegramToken  = Get-DotEnvValue 'TELEGRAM_BOT_TOKEN'
$telegramChatId = Get-DotEnvValue 'TELEGRAM_CHAT_ID'
$ntfyTopic      = Get-DotEnvValue 'ALERT_RELAY_NTFY_TOPIC'
# Use public URL (reachable from Azure); falls back to internal URL if not set
$ntfyPublicUrl  = try { Get-DotEnvValue 'ALERT_RELAY_NTFY_PUBLIC_URL' } catch { Get-DotEnvValue 'ALERT_RELAY_NTFY_URL' }
$ntfyTopicUrl   = "${ntfyPublicUrl}/${ntfyTopic}"

# --- Step 1: deploy the playbook ---
Write-Host 'Deploying notify-playbook...' -ForegroundColor Yellow
$playbookArgs = @(
    'deployment', 'group', 'create',
    '--resource-group', $ResourceGroup,
    '--template-file', "$here/notify-playbook.bicep",
    '--parameters',
        "location=$Location",
        "telegramBotToken=$telegramToken",
        "telegramChatId=$telegramChatId",
        "ntfyTopicUrl=$ntfyTopicUrl",
    '--output', 'json'
)
if ($WhatIf) {
    az @playbookArgs --what-if
    return
}

$result    = az @playbookArgs | ConvertFrom-Json
$playbookId   = $result.properties.outputs.playbookId.value
$playbookName = $result.properties.outputs.playbookName.value
Write-Host "Playbook deployed : $playbookName" -ForegroundColor Green

# --- Step 2: deploy the automation rule ---
Write-Host 'Deploying automation rule...' -ForegroundColor Yellow
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$here/automation-rule.bicep" `
    --parameters workspaceName=$WorkspaceName playbookId=$playbookId `
    --output table

Write-Host 'Done.' -ForegroundColor Green
Write-Host '' -ForegroundColor Green
Write-Host 'POST-DEPLOY (one-time, portal only):' -ForegroundColor Yellow
Write-Host '  Sentinel → Automation → Active playbooks → Manage playbook permissions' -ForegroundColor Yellow
Write-Host '  → select resource group rg-sentinel → Apply' -ForegroundColor Yellow
Write-Host 'This grants Sentinel permission to invoke the Logic App.' -ForegroundColor Yellow
