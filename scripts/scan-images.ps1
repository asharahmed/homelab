Param(
  [string]$ComposeFile = "docker-compose.yml",
  [string]$EnvFile,
  [switch]$SkipSecretsRender
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
  throw "Trivy is not installed or not on PATH."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker is not installed or not on PATH."
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$composePath = Join-Path $repoRoot $ComposeFile
$trivyConfig = Join-Path $repoRoot "tools\security\trivy\trivy.yaml"
$trivyIgnore = Join-Path $repoRoot "tools\security\trivy\ignore.yaml"
$cacheDir = Join-Path ([System.IO.Path]::GetTempPath()) ("trivy-image-cache-" + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $composePath)) {
  throw "Compose file not found: $composePath"
}

New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

Push-Location $repoRoot
try {
  if (-not $SkipSecretsRender) {
    & "$PSScriptRoot\render-secrets-from-infisical.ps1" | Out-Host
  }

  if (-not $EnvFile) {
    $EnvFile = (& "$PSScriptRoot\build-compose-env.ps1").Trim()
  }

  $images = & docker compose --env-file $EnvFile -f $composePath config --images | Sort-Object -Unique

  foreach ($image in $images) {
    if ([string]::IsNullOrWhiteSpace($image)) {
      continue
    }

    Write-Host "Scanning image: $image"
    & trivy image --config $trivyConfig --ignorefile $trivyIgnore --cache-dir $cacheDir --scanners vuln,secret $image
    if ($LASTEXITCODE -ne 0) {
      throw "Trivy image scan failed for $image"
    }
  }
} finally {
  Pop-Location
  if (Test-Path -LiteralPath $cacheDir) {
    Remove-Item -LiteralPath $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
