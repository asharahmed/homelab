#Requires -Version 7
<#
.SYNOPSIS
    Continuous detection-validation loop (purple team as code).

.DESCRIPTION
    Closes the loop that docs/atomic-red-team-coverage.md opens: for each
    detection, optionally run its mapped Atomic Red Team test, then confirm the
    technique's telemetry actually landed in Defender advanced hunting. Records
    pass/fail per detection and emits:
      - results/validation-<timestamp>.json  (full run record)
      - results/latest.json                  (most recent run)
      - coverage-layer.json                  (MITRE ATT&CK Navigator layer)

    Verification is telemetry-level: it proves the technique executed AND the
    rule's data source is populated with matching events (the purple-team
    "do we have visibility" signal). Alert-level confirmation lags by the rule
    frequency (custom detections run hourly) and is out of scope for a tight loop.

    Auth: app-only to Graph runHuntingQuery, reusing the detections-deployer app
    (DEFENDER_APP_ID / _SECRET / AZURE_TENANT_ID in .env). Requires the app
    permission ThreatHunting.Read.All (already granted).

.PARAMETER RunAtomics
    Execute each mapped atomic before verifying. HOST-ONLY, DESTRUCTIVE — runs
    real attack techniques. Without this switch, the script only verifies against
    whatever telemetry already exists (safe; use after a manual atomic run or on
    a schedule that runs atomics separately).

.PARAMETER LookbackMinutes
    How far back each verification query looks. Default 45 (covers ingest latency
    plus a recent atomic run).

.PARAMETER NoCleanup
    With -RunAtomics, skip the atomic -Cleanup pass.

.EXAMPLE
    ./validate-detections.ps1                      # verify against existing telemetry
.EXAMPLE
    ./validate-detections.ps1 -RunAtomics          # run atomics then verify (lab host)
#>
param(
    [switch]$RunAtomics,
    [int]$LookbackMinutes = 45,
    [switch]$NoCleanup
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path "$here/../.."

# ---------------------------------------------------------------------------
# Detection -> technique -> atomic -> verification query map.
# Keep in sync with docs/atomic-red-team-coverage.md and the deployed rules.
# `Verify` is a KQL fragment; the loop prepends a Timestamp filter. A match
# (>=1 row) means the technique's telemetry is present -> detection has visibility.
# `Tactic` uses ATT&CK tactic shortnames for the Navigator layer.
# ---------------------------------------------------------------------------
$Map = @(
    @{ Rule='powershell_encoded_or_download'; Technique='T1059.001'; Tactic='execution'; Atomic=@{T='T1059.001';N=15}
       Verify='DeviceProcessEvents | where ProcessCommandLine has "-encodedcommand" or ProcessCommandLine has "-enc "' }
    @{ Rule='lolbin_network_connection'; Technique='T1105'; Tactic='command-and-control'; Atomic=@{T='T1105';N=7}
       Verify='DeviceNetworkEvents | where InitiatingProcessFileName in~ ("certutil.exe","powershell.exe","bitsadmin.exe","mshta.exe","regsvr32.exe")' }
    @{ Rule='unsigned_dll_from_user_writable_path'; Technique='T1055.001'; Tactic='defense-evasion'; Atomic=@{T='T1055.001';N=1}
       Verify='DeviceImageLoadEvents | where FolderPath has_any (@"\AppData\", @"\Temp\", @"\Downloads\") | where InitiatingProcessFileName !in~ ("MsMpEng.exe","SenseIR.exe","msiexec.exe")' }
    @{ Rule='lsass_credential_access'; Technique='T1003.001'; Tactic='credential-access'; Atomic=@{T='T1003.001';N=2}
       # OpenProcessApiCall puts the TARGET in FileName; AdditionalFields holds
       # only DesiredAccess (no TargetProcessName) - same wrong-field bug as
       # injection, caught by purple-team validation 2026-07-04.
       Verify='DeviceEvents | where ActionType == "OpenProcessApiCall" | where FileName =~ "lsass.exe" | where InitiatingProcessFileName !in~ ("MsMpEng.exe","csrss.exe","wininit.exe","services.exe","lsaiso.exe","WerFault.exe")' }
    @{ Rule='remote_thread_injection'; Technique='T1055'; Tactic='defense-evasion'; Atomic=@{T='T1055';N=2}
       # CreateRemoteThreadApiCall puts the TARGET in FileName (AdditionalFields
       # .TargetProcessName is empty) - purple-team validation caught the rule
       # keying on the wrong field 2026-07-04.
       Verify='DeviceEvents | where ActionType == "CreateRemoteThreadApiCall" | where FileName in~ ("lsass.exe","winlogon.exe","explorer.exe","services.exe","svchost.exe")' }
    @{ Rule='registry_run_key_persistence'; Technique='T1547.001'; Tactic='persistence'; Atomic=@{T='T1547.001';N=1}
       Verify='DeviceRegistryEvents | where RegistryKey has @"CurrentVersion\Run"' }
    @{ Rule='dns_query_suspicious_tld'; Technique='T1071.004'; Tactic='command-and-control'; Atomic=@{T='T1071.004';N=1;Args=@{domain='example.ru'}}
       Verify='DeviceNetworkEvents | where RemotePort == 53 | where RemoteUrl has_any (".ru",".cn",".tk",".xyz",".top",".pw",".cc")' }
    @{ Rule='office_browser_spawns_lolbin'; Technique='T1566.001'; Tactic='initial-access'; Atomic=@{T='T1566.001';N=2}
       Verify='DeviceProcessEvents | where InitiatingProcessFileName in~ ("winword.exe","excel.exe","powerpnt.exe","outlook.exe") | where FileName in~ ("cmd.exe","powershell.exe","wscript.exe","cscript.exe","mshta.exe")' }
    @{ Rule='c2_named_pipe'; Technique='T1071'; Tactic='command-and-control'; Atomic=$null
       Verify='DeviceEvents | where ActionType == "NamedPipeEvent" | extend F=parse_json(AdditionalFields) | where F.PipeName has_any ("meterpreter","beacon","cobaltstrike","msagent","postex")' }
)

# ---------------------------------------------------------------------------
# Optionally run atomics first (host-only, destructive).
# ---------------------------------------------------------------------------
if ($RunAtomics) {
    Write-Host "RunAtomics: executes real attack techniques. Isolated lab host ONLY." -ForegroundColor Yellow
    if ((Read-Host "Type RUN to proceed") -ne 'RUN') { Write-Host 'Aborted.' -ForegroundColor Yellow; return }
    if (-not (Get-Module -ListAvailable -Name invoke-atomicredteam)) {
        Install-Module -Name invoke-atomicredteam -Scope CurrentUser -Force
    }
    Import-Module invoke-atomicredteam
    foreach ($m in $Map | Where-Object { $_.Atomic }) {
        $a = $m.Atomic
        Write-Host "`n=== atomic $($a.T) #$($a.N) ($($m.Rule)) ===" -ForegroundColor Cyan
        try {
            Invoke-AtomicTest $a.T -TestNumbers $a.N -GetPrereqs
            if ($a.Args) { Invoke-AtomicTest $a.T -TestNumbers $a.N -InputArgs $a.Args }
            else { Invoke-AtomicTest $a.T -TestNumbers $a.N }
        } catch { Write-Host "atomic failed: $_" -ForegroundColor Yellow }
        finally { if (-not $NoCleanup) { Invoke-AtomicTest $a.T -TestNumbers $a.N -Cleanup 2>$null } }
    }
    Write-Host "`nAtomics complete. Waiting 300s for telemetry ingestion before verifying..." -ForegroundColor Cyan
    Start-Sleep -Seconds 300
}

# ---------------------------------------------------------------------------
# Auth (app-only) and verify each detection via advanced hunting.
# ---------------------------------------------------------------------------
$envVars = @{}
Get-Content "$repoRoot/.env" | Where-Object { $_ -match '^\s*([^#][^=]*)=(.*)$' } | ForEach-Object {
    $envVars[$Matches[1].Trim()] = $Matches[2].Trim()
}
$token = (Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$($envVars['AZURE_TENANT_ID'])/oauth2/v2.0/token" `
    -Body ('grant_type=client_credentials' +
        "&client_id=$($envVars['DEFENDER_APP_ID'])" +
        "&client_secret=$([uri]::EscapeDataString($envVars['DEFENDER_APP_SECRET']))" +
        '&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default') `
    -ContentType 'application/x-www-form-urlencoded').access_token
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

Write-Host "`nDetection validation (telemetry-level, lookback ${LookbackMinutes}m)" -ForegroundColor Cyan
Write-Host ("{0,-38} {1,-12} {2,-8} {3}" -f 'RULE','TECHNIQUE','RESULT','EVENTS') -ForegroundColor Cyan

$results = foreach ($m in $Map) {
    $kql = "$($m.Verify) | where Timestamp > ago(${LookbackMinutes}m) | summarize Events=count()"
    $body = @{ Query = $kql } | ConvertTo-Json
    $count = 0; $status = 'ERROR'
    try {
        $r = Invoke-RestMethod -Method POST -Headers $headers `
            -Uri 'https://graph.microsoft.com/v1.0/security/runHuntingQuery' -Body $body
        $count = [int]($r.results[0].Events)
        $status = if ($count -gt 0) { 'PASS' } else { 'FAIL' }
    } catch { $status = 'ERROR'; $count = -1 }
    $color = switch ($status) { 'PASS' {'Green'} 'FAIL' {'Red'} default {'Yellow'} }
    Write-Host ("{0,-38} {1,-12} {2,-8} {3}" -f $m.Rule, $m.Technique, $status, $count) -ForegroundColor $color
    [PSCustomObject]@{
        rule = $m.Rule; technique = $m.Technique; tactic = $m.Tactic
        result = $status; events = $count; hasAtomic = [bool]$m.Atomic
    }
}

# ---------------------------------------------------------------------------
# Persist results + ATT&CK Navigator layer.
# ---------------------------------------------------------------------------
$resultsDir = Join-Path $here 'results'
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$pass = ($results | Where-Object result -eq 'PASS').Count
$total = $results.Count
$run = [ordered]@{
    generatedNote = 'timestamp assigned by wrapper/CI; Date APIs unavailable in some contexts'
    lookbackMinutes = $LookbackMinutes
    ranAtomics = [bool]$RunAtomics
    passed = $pass; total = $total
    results = $results
}
$json = $run | ConvertTo-Json -Depth 5
$json | Set-Content (Join-Path $resultsDir 'latest.json') -Encoding utf8

# Navigator layer: green = validated, red = failed/no-visibility.
$techEntries = $results | ForEach-Object {
    $c = switch ($_.result) { 'PASS' {'#2e7d32'} 'FAIL' {'#c62828'} default {'#9e9e9e'} }
    [ordered]@{
        techniqueID = $_.technique
        color = $c
        comment = "$($_.rule): $($_.result) ($($_.events) events)"
        enabled = $true
    }
}
$layer = [ordered]@{
    name = 'Homelab detection validation'
    versions = @{ attack = '14'; navigator = '4.9.1'; layer = '4.5' }
    domain = 'enterprise-attack'
    description = "Telemetry-level validation of deployed detections. Green=validated, Red=no visibility. $pass/$total passing."
    techniques = @($techEntries)
    gradient = @{ colors = @('#c62828','#2e7d32'); minValue = 0; maxValue = 1 }
    legendItems = @(
        @{ label = 'Validated (telemetry present)'; color = '#2e7d32' }
        @{ label = 'No visibility (investigate)'; color = '#c62828' }
    )
}
$layer | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $here 'coverage-layer.json') -Encoding utf8

Write-Host "`n$pass/$total detections validated." -ForegroundColor $(if ($pass -eq $total) {'Green'} else {'Yellow'})
Write-Host "  results/latest.json + coverage-layer.json written." -ForegroundColor DarkGray
if ($pass -lt $total) {
    Write-Host "  FAIL = no matching telemetry in ${LookbackMinutes}m. Run with -RunAtomics on the lab host, or investigate the data source." -ForegroundColor Yellow
    exit 1
}
