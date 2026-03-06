Param(
  [string]$Version = '0.30.5',
  [string]$DownloadDir = "$env:TEMP"
)

$ErrorActionPreference = 'Stop'

$msiName = "windows_exporter-$Version-amd64.msi"
$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v$Version/$msiName"
$msiPath = Join-Path $DownloadDir $msiName

Write-Host "Downloading windows_exporter $Version..."
Invoke-WebRequest -Uri $url -OutFile $msiPath

Write-Host "Installing service..."
Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" LISTEN_PORT=9182 LISTEN_ADDR=0.0.0.0 /quiet /norestart" -Wait -NoNewWindow

Write-Host "Ensuring service is running..."
Start-Service -Name windows_exporter -ErrorAction SilentlyContinue
Set-Service -Name windows_exporter -StartupType Automatic

# Optional: open firewall for local LAN access only
if (-not (Get-NetFirewallRule -DisplayName "windows_exporter_9182" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "windows_exporter_9182" -Direction Inbound -LocalPort 9182 -Protocol TCP -Action Allow -Profile Private | Out-Null
}

Write-Host "windows_exporter installed. Verify with:  Invoke-WebRequest http://localhost:9182/metrics"
