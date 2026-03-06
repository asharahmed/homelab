Param(
  [string]$ExporterExe = "C:\Program Files\windows_exporter\windows_exporter.exe",
  [string]$MetricScript = "C:\Program Files\windows_exporter\scripts\export-windows-security-metrics.ps1"
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$sourceScript = Join-Path $repoRoot "scripts\export-windows-security-metrics.ps1"
$scriptDir = Split-Path -Parent $MetricScript
$textfileDir = "C:\Program Files\windows_exporter\textfile_inputs"

foreach ($dir in @($scriptDir, $textfileDir, "C:\ProgramData\windows_exporter")) {
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

Copy-Item -LiteralPath $sourceScript -Destination $MetricScript -Force

$configFile = "C:\Program Files\windows_exporter\config.yaml"
$binPath = '"{0}" --config.file="{1}" --collectors.enabled "[defaults],textfile" --collector.textfile.directories="{2}"' -f $ExporterExe, $configFile, $textfileDir
$service = Get-CimInstance Win32_Service -Filter "Name='windows_exporter'"
if (-not $service) {
  throw "windows_exporter service not found."
}
$result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{ PathName = $binPath }
if ($result.ReturnValue -ne 0) {
  throw "Failed to update windows_exporter service PathName (ReturnValue=$($result.ReturnValue))."
}

$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$MetricScript`""
$taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
$taskSettings = New-ScheduledTaskSettingsSet
Register-ScheduledTask -TaskName "WindowsSecurityMetricsExporter" -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MetricScript
Restart-Service windows_exporter

Write-Host "windows_exporter textfile metric installed and service restarted."
