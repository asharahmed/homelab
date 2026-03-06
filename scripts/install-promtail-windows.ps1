Param(
  [string]$Version = "3.0.0"
)

$ErrorActionPreference = "Stop"

$baseDir = "C:\Program Files\promtail-windows"
$dataDir = "C:\ProgramData\promtail"
# Correct artifact name for Loki 3.x
$zipUrl  = "https://github.com/grafana/loki/releases/download/v$Version/promtail-windows-amd64.exe.zip"
$zipPath = Join-Path $env:TEMP "promtail-$Version.zip"
$configSrc = Join-Path (Split-Path -Parent $PSCommandPath | Split-Path -Parent) "tools\monitoring\promtail-windows.yml"
$configDst = Join-Path $dataDir "promtail-windows.yml"

Write-Host "Downloading promtail $Version..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

Write-Host "Extracting to $baseDir..." -ForegroundColor Cyan
if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir | Out-Null }
Expand-Archive -Path $zipPath -DestinationPath $baseDir -Force

Write-Host "Preparing data directories..." -ForegroundColor Cyan
foreach ($d in @($dataDir, "$dataDir\bookmarks")) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

Write-Host "Staging config..." -ForegroundColor Cyan
Copy-Item -Path $configSrc -Destination $configDst -Force

$svcName = "promtail-windows"
$exePath = Join-Path $baseDir "promtail-windows-amd64.exe"
$binPath = "`"$exePath`" --config.file=`"$configDst`""

if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
  Write-Host "Service exists; stopping and reconfiguring..." -ForegroundColor Yellow
  Stop-Service $svcName -ErrorAction SilentlyContinue
  sc.exe delete $svcName | Out-Null
}

Write-Host "Installing Windows service $svcName..." -ForegroundColor Cyan
if (-not (Get-Command New-Service -ErrorAction SilentlyContinue)) {
  sc.exe create $svcName binPath= $binPath start= auto DisplayName= "Promtail (Loki)" | Out-Null
} else {
  New-Service -Name $svcName -BinaryPathName $binPath -DisplayName "Promtail (Loki)" -StartupType Automatic | Out-Null
}

Write-Host "Starting service..." -ForegroundColor Cyan
Start-Service $svcName

Write-Host "Promtail installed. Verify with: Get-Service $svcName and http://localhost:9081/metrics" -ForegroundColor Green
