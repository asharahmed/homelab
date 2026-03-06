Param(
  [string]$ComposeFile = "docker-compose.yml",
  [switch]$SkipImageScan
)

$ErrorActionPreference = 'Stop'

function Section($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

Section "Rendering secrets"
& "$PSScriptRoot\render-secrets-from-infisical.ps1" | Out-Host

Section "Building compose env"
$envFile = (& "$PSScriptRoot\build-compose-env.ps1").Trim()
Write-Host "Using compose env: $envFile"

Section "Repository security scan"
& "$PSScriptRoot\validate-security.ps1" | Out-Host

if (-not $SkipImageScan) {
  Section "Container image scan"
  & "$PSScriptRoot\scan-images.ps1" -ComposeFile $ComposeFile -EnvFile $envFile -SkipSecretsRender | Out-Host
}
