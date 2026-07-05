#Requires -Version 7
<#
.SYNOPSIS
    Register a scheduled task that runs verify-only detection validation on a
    cadence, to catch coverage drift (broken data source, EDR gap, renamed table)
    between purple-team windows.

.DESCRIPTION
    Runs validate-detections.ps1 (NO -RunAtomics — safe, non-destructive) weekly.
    A non-zero exit (any detection failed to validate) is left in the task's last
    result so it surfaces in Task Scheduler; wire to ntfy/alerting if desired.

    The destructive -RunAtomics pass is intentionally NOT scheduled: run it
    manually on an isolated lab host during a dedicated purple-team window.

.EXAMPLE
    ./schedule-validation.ps1              # register weekly (Sun 05:00)
.EXAMPLE
    ./schedule-validation.ps1 -Unregister
#>
param(
    [string]$Time = '05:00',
    [string]$DaysOfWeek = 'Sunday',
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'
$taskName = 'Detection-Validation-DriftCheck'
$script = Join-Path $PSScriptRoot 'validate-detections.ps1'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Unregistered $taskName" -ForegroundColor Green
    return
}

$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DaysOfWeek -At $Time
# Local accounts report USERDOMAIN=WORKGROUP which won't map; use COMPUTERNAME.
$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" `
    -LogonType S4U -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Registered '$taskName': verify-only validation every $DaysOfWeek at $Time" -ForegroundColor Green
Write-Host "  (destructive -RunAtomics is manual, isolated-host only)" -ForegroundColor DarkGray
