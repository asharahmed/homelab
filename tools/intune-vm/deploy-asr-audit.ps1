#Requires -Version 7
<#
.SYNOPSIS
    Deploy the standard Attack Surface Reduction (ASR) rule set to Intune-managed
    Windows devices in AUDIT mode, as code.

.DESCRIPTION
    Builds a Settings Catalog configuration policy (endpointSecurityAttackSurface
    Reduction template) that sets every ASR choice rule to "audit", then assigns
    it to all devices. Audit mode is the recommended first step: it logs what
    each rule WOULD block without breaking anything, so telemetry can be reviewed
    (Defender advanced hunting: DeviceEvents ActionType 'Asr*Audited') before
    flipping to block.

    Idempotent: matched on policy name. Graph app permission required on the
    detections-deployer app: DeviceManagementConfiguration.ReadWrite.All.

.EXAMPLE
    ./deploy-asr-audit.ps1
#>
param([switch] $WhatIf)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path "$PSScriptRoot/../.."

$envVars = @{}
Get-Content "$repoRoot/.env" | Where-Object { $_ -match '^\s*([^#][^=]*)=(.*)$' } | ForEach-Object {
    $envVars[$Matches[1].Trim()] = $Matches[2].Trim()
}
$formBody = 'grant_type=client_credentials' +
    "&client_id=$($envVars['DEFENDER_APP_ID'])" +
    "&client_secret=$([uri]::EscapeDataString($envVars['DEFENDER_APP_SECRET']))" +
    '&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default'
$token = (Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$($envVars['AZURE_TENANT_ID'])/oauth2/v2.0/token" `
    -Body $formBody -ContentType 'application/x-www-form-urlencoded').access_token
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$templateId = 'e8c053d6-9f95-42b1-a7f1-ebfd71c67a4b_1'  # Attack Surface Reduction Rules
$policyName = 'Endpoint security - ASR rules (audit)'

# Pull the template's ASR choice rules (options: off/block/audit/warn).
$defs = (Invoke-RestMethod -Headers $headers `
    -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates('$templateId')/settingTemplates?`$expand=settingDefinitions").value.settingDefinitions
$asrRules = $defs | Where-Object {
    $_.'@odata.type' -match 'ChoiceSettingDefinition' -and
    ($_.options.itemId -join ' ') -match '_audit'
}
Write-Host "ASR choice rules found: $($asrRules.Count)" -ForegroundColor Cyan

# The ASR rules are children of a group-collection setting; each individual
# rule is a choice setting nested inside one group instance.
$parentId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
$children = foreach ($rule in $asrRules) {
    $auditOption = ($rule.options | Where-Object { $_.itemId -match '_audit$' }).itemId
    @{
        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
        settingDefinitionId = $rule.id
        choiceSettingValue = @{
            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
            value = $auditOption
            children = @()
        }
    }
}

$body = @{
    name         = $policyName
    description  = 'Standard ASR rule set in audit mode. Deployed as code (tools/intune-vm/deploy-asr-audit.ps1). Review DeviceEvents Asr*Audited telemetry before switching to block.'
    platforms    = 'windows10'
    technologies = 'mdm'
    settings     = @(
        @{
            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = @{
                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                settingDefinitionId = $parentId
                groupSettingCollectionValue = @(
                    @{ children = @($children) }
                )
            }
        }
    )
}

$policiesUrl = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
$existing = (Invoke-RestMethod -Headers $headers -Uri "$policiesUrl`?`$filter=name eq '$policyName'").value |
    Select-Object -First 1

if ($WhatIf) {
    Write-Host "WHATIF $(if($existing){'UPDATE'}else{'CREATE'}) : $policyName ($($children.Count) rules -> audit)" -ForegroundColor Yellow
    return
}

if ($existing) {
    Invoke-RestMethod -Uri "$policiesUrl/$($existing.id)" -Headers $headers -Method PUT `
        -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    $policyId = $existing.id
    Write-Host "Updated : $policyName" -ForegroundColor Green
} else {
    $created = Invoke-RestMethod -Uri $policiesUrl -Headers $headers -Method POST `
        -Body ($body | ConvertTo-Json -Depth 12)
    $policyId = $created.id
    Write-Host "Created : $policyName (id=$policyId)" -ForegroundColor Green
}

$assign = @{ assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }) } |
    ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri "$policiesUrl/$policyId/assign" -Headers $headers -Method POST -Body $assign | Out-Null
Write-Host "Assigned to all devices ($($children.Count) ASR rules in audit)." -ForegroundColor Green
