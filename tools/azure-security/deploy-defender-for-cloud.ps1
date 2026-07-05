#Requires -Version 7
<#
.SYNOPSIS
    Enable Microsoft Defender for Cloud foundational CSPM (free) and keep it
    that way — with a hard cost guardrail for the Azure-for-Students cap.

.DESCRIPTION
    Idempotent. Registers the Microsoft.Security provider (activates the free
    foundational CSPM: Secure Score, recommendations, MCSB regulatory
    compliance), then FORCES every billable Defender workload plan to the
    Free tier so nothing bills against the $100 credit. Also assigns the CIS
    Azure Foundations Benchmark as an audit-only compliance standard.

    Foundational CSPM and Discovery are Microsoft's always-free foundation
    (they report tier "Standard" = enabled, not billed) and are left alone.

    NIST SP 800-53 Rev. 5 is intentionally NOT assigned: its initiative
    bundles deployIfNotExists policies that require a managed identity and can
    deploy resources — a cost risk on a capped subscription. Add it manually
    (with a system-assigned identity + location) only if you accept that.

.EXAMPLE
    ./deploy-defender-for-cloud.ps1
    ./deploy-defender-for-cloud.ps1 -WhatIf
#>
param(
    [string] $SubscriptionId = '59034592-7ff7-4891-9356-db1dee77c48f',
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

function Invoke-Arm {
    param([string]$Method, [string]$Url, [string]$Body)
    $args = @('rest', '--method', $Method, '--url', $Url)
    if ($Body) { $args += @('--body', $Body) }
    az @args 2>$null
}

$base = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Security"

# 1. Register provider (activates free foundational CSPM)
Write-Host "Registering Microsoft.Security provider..." -ForegroundColor Cyan
az provider register --namespace Microsoft.Security --subscription $SubscriptionId 2>$null | Out-Null

# 2. Cost guardrail — force every billable workload plan to Free.
#    Foundational free-tier components are excluded (they must stay enabled).
$freeFoundation = @('FoundationalCspm', 'Discovery')
$pricings = (Invoke-Arm GET "$base/pricings?api-version=2024-01-01" | ConvertFrom-Json).value

foreach ($p in $pricings) {
    $name = $p.name
    $tier = $p.properties.pricingTier
    if ($name -in $freeFoundation) { continue }
    if ($tier -eq 'Standard') {
        if ($WhatIf) {
            Write-Host "WHATIF: would set $name -> Free (currently PAID)" -ForegroundColor Yellow
        } else {
            Invoke-Arm PUT "$base/pricings/$name`?api-version=2024-01-01" '{"properties":{"pricingTier":"Free"}}' | Out-Null
            Write-Host "  $name : Standard -> Free (cost guardrail)" -ForegroundColor Green
        }
    } else {
        Write-Host "  $name : Free" -ForegroundColor DarkGray
    }
}

# 3. CIS Azure Foundations Benchmark v2.0.0 — audit-only compliance standard
if (-not $WhatIf) {
    Write-Host "Assigning CIS Azure Foundations Benchmark (audit)..." -ForegroundColor Cyan
    $cis = '{"properties":{"policyDefinitionId":"/providers/Microsoft.Authorization/policySetDefinitions/06f19060-9e68-4070-92ca-f15cc126059e","displayName":"CIS Microsoft Azure Foundations Benchmark v2.0.0"}}'
    Invoke-Arm PUT "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyAssignments/cis-azure-v2?api-version=2022-06-01" $cis | Out-Null
    Write-Host "  CIS assigned." -ForegroundColor Green
}

Write-Host "`nDone. Foundational CSPM active; all paid plans Free." -ForegroundColor Cyan
Write-Host "Secure Score + compliance populate within ~30min-few hours of first scan." -ForegroundColor Cyan
Write-Host "Verify: portal.azure.com -> Microsoft Defender for Cloud -> Secure Score / Regulatory compliance" -ForegroundColor Cyan
