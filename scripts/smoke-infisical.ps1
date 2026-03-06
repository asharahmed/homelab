Param(
  [string]$BasePath
)

$ErrorActionPreference = 'Stop'

function Get-EnvValue {
  param(
    [string]$FilePath,
    [string]$Key
  )

  if (-not (Test-Path -LiteralPath $FilePath)) {
    return $null
  }

  $escapedKey = [Regex]::Escape($Key)
  $match = Select-String -Path $FilePath -Pattern "^${escapedKey}=(.*)$" | Select-Object -First 1
  if ($match) {
    return $match.Matches[0].Groups[1].Value.Trim()
  }

  return $null
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$envFile = Join-Path $repoRoot '.env'

if (-not $BasePath -or $BasePath.Trim() -eq '') {
  $BasePath = Get-EnvValue -FilePath $envFile -Key 'BASE_PATH'
}
if (-not $BasePath) {
  $BasePath = 'C:\docker'
}

$bootstrapEnv = Join-Path $BasePath 'infisical\bootstrap\infisical.env'
if (-not (Test-Path -LiteralPath $bootstrapEnv)) {
  throw "Bootstrap env not found: $bootstrapEnv"
}

$siteUrl = Get-EnvValue -FilePath $bootstrapEnv -Key 'SITE_URL'
if (-not $siteUrl) {
  throw 'SITE_URL not found in bootstrap env'
}

$containerStatus = docker inspect infisical --format '{{.State.Status}}'
if ($LASTEXITCODE -ne 0) {
  throw 'Failed to inspect infisical container state'
}
$containerStatus | Write-Host
if ($containerStatus.Trim() -ne 'running') {
  throw 'Infisical container is not running'
}

$headers = curl.exe -skI --max-time 15 "$siteUrl/" 2>&1
if ($LASTEXITCODE -ne 0) {
  throw 'Infisical URL probe failed'
}
$headers | Write-Host
if (-not ($headers | Select-String -SimpleMatch 'HTTP/1.1 200 OK')) {
  throw 'Infisical URL probe did not return HTTP 200'
}
