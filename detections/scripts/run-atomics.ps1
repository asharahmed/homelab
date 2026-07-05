<#
.SYNOPSIS
    Run the Atomic Red Team tests mapped to this repo's detections, to validate
    that each rule's compiled query fires.

.DESCRIPTION
    Executes the Windows + container atomics from docs/atomic-red-team-coverage.md
    with prerequisite fetch and cleanup. Custom-source rules (web/auth/router) are
    validated manually — see the coverage matrix.

    SAFETY: runs real attack techniques. Isolated lab hosts ONLY. Never a daily driver.

.PARAMETER ListOnly
    Print the mapped tests and exit without running anything.

.PARAMETER NoCleanup
    Skip the -Cleanup pass (leave artifacts for inspection).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File run-atomics.ps1 -ListOnly
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File run-atomics.ps1
#>
param(
    [switch]$ListOnly,
    [switch]$NoCleanup
)
$ErrorActionPreference = 'Stop'

# Rule -> technique/test mapping (keep in sync with docs/atomic-red-team-coverage.md)
$Tests = @(
    @{ Rule = 'office_browser_spawns_lolbin';          Technique = 'T1566.001'; Numbers = 2 }
    @{ Rule = 'powershell_encoded_or_download';        Technique = 'T1059.001'; Numbers = 15 }
    @{ Rule = 'lolbin_network_connection';             Technique = 'T1105';     Numbers = 7 }
    @{ Rule = 'unsigned_dll_from_user_writable_path';  Technique = 'T1055.001'; Numbers = 1 }
    @{ Rule = 'lsass_credential_access';               Technique = 'T1003.001'; Numbers = 2 }
    @{ Rule = 'remote_thread_injection';               Technique = 'T1055';     Numbers = 2 }
    @{ Rule = 'registry_run_key_persistence';          Technique = 'T1547.001'; Numbers = 1 }
    @{ Rule = 'dns_query_suspicious_tld';              Technique = 'T1071.004'; Numbers = 1 }
    @{ Rule = 'docker_privileged_container_start';     Technique = 'T1611';     Numbers = 2 }
    @{ Rule = 'docker_container_exec';                 Technique = 'T1609';     Numbers = 2 }
)

Write-Host "Atomic Red Team -> detection validation" -ForegroundColor Cyan
Write-Host ("{0,-38} {1,-12} {2}" -f 'RULE', 'TECHNIQUE', 'TEST#') -ForegroundColor Cyan
foreach ($t in $Tests) {
    Write-Host ("{0,-38} {1,-12} {2}" -f $t.Rule, $t.Technique, $t.Numbers)
}

if ($ListOnly) { return }

Write-Host "`nWARNING: this executes real attack techniques. Isolated lab only." -ForegroundColor Yellow
$confirm = Read-Host "Type RUN to proceed"
if ($confirm -ne 'RUN') { Write-Host "Aborted." -ForegroundColor Yellow; return }

if (-not (Get-Module -ListAvailable -Name invoke-atomicredteam)) {
    Write-Host "Installing invoke-atomicredteam..." -ForegroundColor Cyan
    Install-Module -Name invoke-atomicredteam -Scope CurrentUser -Force
}
Import-Module invoke-atomicredteam

foreach ($t in $Tests) {
    Write-Host "`n=== $($t.Rule): $($t.Technique) #$($t.Numbers) ===" -ForegroundColor Cyan
    try {
        Invoke-AtomicTest $t.Technique -TestNumbers $t.Numbers -GetPrereqs
        Invoke-AtomicTest $t.Technique -TestNumbers $t.Numbers
        Write-Host "ran $($t.Technique) #$($t.Numbers) -- confirm '$($t.Rule)' fired in the SIEM" -ForegroundColor Green
    } catch {
        Write-Host "FAILED $($t.Technique) #$($t.Numbers): $_" -ForegroundColor Yellow
    } finally {
        if (-not $NoCleanup) {
            Invoke-AtomicTest $t.Technique -TestNumbers $t.Numbers -Cleanup
        }
    }
}

Write-Host "`nDone. Cross-check each rule's compiled query in the SIEM against the runs above." -ForegroundColor Green
