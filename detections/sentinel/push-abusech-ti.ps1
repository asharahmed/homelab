#Requires -Version 7
<#
.SYNOPSIS
    Ingest abuse.ch ThreatFox IOCs into Microsoft Sentinel as STIX 2.1
    indicators via the Threat Intelligence Upload API.

.DESCRIPTION
    abuse.ch retired STIX/TAXII, so this replaces a TAXII connector with a
    direct pipeline: pull recent ThreatFox IOCs (free JSON API, Auth-Key),
    map each to a STIX 2.1 indicator with a deterministic UUIDv5 id (so
    re-runs update rather than duplicate), and POST in batches to Sentinel's
    upload API. Indicators land in the ThreatIntelligenceIndicator table.

    Auth to Sentinel: Azure CLI token for https://management.azure.com. The
    caller needs Microsoft Sentinel Contributor on the workspace (subscription
    Owner satisfies this).

    Required .env: ABUSECH_AUTH_KEY  (free from https://auth.abuse.ch/)

.EXAMPLE
    ./push-abusech-ti.ps1 -Days 1
    ./push-abusech-ti.ps1 -Days 3 -WhatIf
#>
param(
    [ValidateRange(1,7)] [int] $Days = 1,
    [string] $WorkspaceId = '66b6810a-9b6d-41b7-97d2-00dcda77f306',
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path "$PSScriptRoot/../.."

# --- creds ---
$authKey = (Get-Content "$repoRoot/.env" | Where-Object { $_ -match '^\s*ABUSECH_AUTH_KEY=(.+)$' } | Select-Object -First 1) -replace '^\s*ABUSECH_AUTH_KEY=', ''
$authKey = $authKey.Trim()
if (-not $authKey) { throw 'ABUSECH_AUTH_KEY missing from .env (get one free at https://auth.abuse.ch/)' }

# --- deterministic UUIDv5 (RFC 4122) so the same IOC keeps the same STIX id ---
$NS = '1b4e28ba-2fa1-11d2-883f-0016d3cca427'   # fixed homelab namespace
function New-UuidV5 {
    param([string]$Name)
    $ns = [guid]::Parse($script:NS).ToByteArray()
    [Array]::Reverse($ns,0,4); [Array]::Reverse($ns,4,2); [Array]::Reverse($ns,6,2)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $h = $sha1.ComputeHash($ns + [System.Text.Encoding]::UTF8.GetBytes($Name))
    $b = $h[0..15]
    $b[6] = ($b[6] -band 0x0F) -bor 0x50   # version 5
    $b[8] = ($b[8] -band 0x3F) -bor 0x80   # RFC variant
    [Array]::Reverse($b,0,4); [Array]::Reverse($b,4,2); [Array]::Reverse($b,6,2)
    ([guid]::new([byte[]]$b)).ToString()
}

function ConvertTo-StixPattern {
    param([string]$Type, [string]$Ioc)
    $esc = { param($s) $s -replace '\\','\\' -replace "'","\'" }
    switch ($Type) {
        'ip:port'     { $ip = ($Ioc -split ':')[0]; $k = if ($ip -match ':') {'ipv6-addr'} else {'ipv4-addr'}; "[$k`:value = '$(& $esc $ip)']" }
        'domain'      { "[domain-name:value = '$(& $esc $Ioc)']" }
        'url'         { "[url:value = '$(& $esc $Ioc)']" }
        'md5_hash'    { "[file:hashes.'MD5' = '$(& $esc $Ioc)']" }
        'sha256_hash' { "[file:hashes.'SHA-256' = '$(& $esc $Ioc)']" }
        default       { $null }
    }
}

# --- fetch ThreatFox IOCs ---
Write-Host "Fetching ThreatFox IOCs (last $Days day(s))..." -ForegroundColor Cyan
$resp = Invoke-RestMethod -Uri 'https://threatfox-api.abuse.ch/api/v1/' -Method POST `
    -Headers @{ 'Auth-Key' = $authKey } `
    -Body (@{ query = 'get_iocs'; days = $Days } | ConvertTo-Json) -ContentType 'application/json'
if ($resp.query_status -ne 'ok') { throw "ThreatFox query failed: $($resp.query_status)" }
$iocs = $resp.data
Write-Host "  $($iocs.Count) IOCs returned" -ForegroundColor Green

# --- map to STIX 2.1 indicators ---
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$stix = foreach ($i in $iocs) {
    $pattern = ConvertTo-StixPattern -Type $i.ioc_type -Ioc $i.ioc
    if (-not $pattern) { continue }
    $validFrom = try { ([datetime]$i.first_seen).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } catch { $now }
    $validUntil = try { ([datetime]$i.first_seen).ToUniversalTime().AddDays(90).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } catch { (Get-Date).ToUniversalTime().AddDays(90).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
    $labels = @($i.malware_printable, $i.threat_type) + @($i.tags) | Where-Object { $_ }
    [ordered]@{
        type          = 'indicator'
        spec_version  = '2.1'
        id            = "indicator--$(New-UuidV5 -Name $i.ioc)"
        created       = $now
        modified      = $now
        name          = "ThreatFox: $($i.malware_printable) ($($i.ioc_type))"
        description   = "abuse.ch ThreatFox | threat_type=$($i.threat_type) | malware=$($i.malware) | ref=$($i.reference)"
        indicator_types = @('malicious-activity')
        pattern       = $pattern
        pattern_type  = 'stix'
        valid_from    = $validFrom
        valid_until   = $validUntil
        confidence    = [int]($i.confidence_level)
        labels        = @($labels)
    }
}
Write-Host "  mapped $($stix.Count) STIX indicators" -ForegroundColor Green
if ($stix.Count -eq 0) { Write-Host 'Nothing to upload.' -ForegroundColor Yellow; return }

if ($WhatIf) {
    Write-Host "WHATIF: would upload $($stix.Count) indicators. Sample:" -ForegroundColor Yellow
    $stix[0] | ConvertTo-Json -Depth 4
    return
}

# --- Sentinel upload API ---
$env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$token = az account get-access-token --resource 'https://management.azure.com' --query accessToken -o tsv
if (-not $token) { throw 'Failed to get ARM token (run: az login --use-device-code)' }
$uri = "https://api.ti.sentinel.azure.com/workspaces/$WorkspaceId/threat-intelligence-stix-objects:upload?api-version=2024-02-01-preview"
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

# batch ≤100 objects/request (API limit)
$batchSize = 100; $uploaded = 0; $errors = 0
for ($n = 0; $n -lt $stix.Count; $n += $batchSize) {
    $batch = $stix[$n..([Math]::Min($n + $batchSize - 1, $stix.Count - 1))]
    $body = @{ sourcesystem = 'abuse.ch ThreatFox'; stixobjects = @($batch) } | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-RestMethod -Uri $uri -Headers $headers -Method POST -Body $body
        if ($r.errors) { $errors += $r.errors.Count; Write-Host "  batch $([int]($n/$batchSize)+1): $($r.errors.Count) validation error(s)" -ForegroundColor Yellow }
        $uploaded += $batch.Count
        Write-Host "  uploaded batch $([int]($n/$batchSize)+1) ($($batch.Count) objects)" -ForegroundColor Green
    } catch {
        Write-Host "  batch $([int]($n/$batchSize)+1) FAILED: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}
Write-Host "Done. Uploaded $uploaded indicator(s), $errors validation error(s)." -ForegroundColor Cyan
# NOTE: query the current TI table 'ThreatIntelIndicators' — the legacy
# 'ThreatIntelligenceIndicator' (singular) is deprecated and stays empty.
Write-Host "Verify: ThreatIntelIndicators | where SourceSystem == 'abuse.ch ThreatFox' | summarize count()" -ForegroundColor Cyan
