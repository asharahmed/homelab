Param(
  [string]$MetricsPath = "C:\Program Files\windows_exporter\textfile_inputs\windows-security.prom",
  [string]$StatePath = "C:\ProgramData\windows_exporter\windows-security-state.json"
)

$ErrorActionPreference = 'Stop'

$stateDir = Split-Path -Parent $StatePath
$metricsDir = Split-Path -Parent $MetricsPath

foreach ($dir in @($stateDir, $metricsDir)) {
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

$latestEvent = Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction Stop
$latestRecordId = [int64]$latestEvent.RecordId

if (Test-Path $StatePath) {
  $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
} else {
  $state = [pscustomobject]@{
    last_record_id = $latestRecordId
    failed_logons = 0
  }
}

if ([int64]$state.last_record_id -gt $latestRecordId) {
  $state.last_record_id = $latestRecordId
  $state.failed_logons = 0
}

$newFailures = @()
if ([int64]$state.last_record_id -lt $latestRecordId) {
  $filter = "*[System[(EventID=4625) and EventRecordID > $([int64]$state.last_record_id)]]"
  $newFailures = @(Get-WinEvent -LogName Security -FilterXPath $filter -ErrorAction SilentlyContinue)
}

$state.failed_logons = [int64]$state.failed_logons + $newFailures.Count
$state.last_record_id = $latestRecordId
$state | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8

$metrics = @(
  "# HELP windows_eventlog_security_total Cumulative count of Security log events exported from Windows."
  "# TYPE windows_eventlog_security_total counter"
  ('windows_eventlog_security_total{{host="windows",event_id="4625"}} {0}' -f [int64]$state.failed_logons)
)

Set-Content -LiteralPath $MetricsPath -Value $metrics -Encoding ascii
