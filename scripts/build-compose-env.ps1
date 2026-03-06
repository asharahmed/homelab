Param(
  [string]$BaseEnvFile = ".env",
  [string]$RenderedSecretsFile,
  [string]$OutputFile
)

$ErrorActionPreference = 'Stop'

function Parse-DotEnv {
  param([string]$Path)

  $map = [ordered]@{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $map
  }

  foreach ($rawLine in Get-Content -LiteralPath $Path) {
    $line = $rawLine.TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#') {
      continue
    }

    $match = [regex]::Match($line, '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
    if (-not $match.Success) {
      continue
    }

    $map[$match.Groups[1].Value] = $match.Groups[2].Value
  }

  return $map
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$baseEnvPath = if ([System.IO.Path]::IsPathRooted($BaseEnvFile)) { $BaseEnvFile } else { Join-Path $repoRoot $BaseEnvFile }

if (-not $RenderedSecretsFile) {
  $baseMap = Parse-DotEnv -Path $baseEnvPath
  $basePath = if ($baseMap.Contains('BASE_PATH')) { $baseMap['BASE_PATH'] } else { 'C:\docker' }
  $RenderedSecretsFile = Join-Path $basePath 'runtime-secrets\homelab.env'
}
if (-not [System.IO.Path]::IsPathRooted($RenderedSecretsFile)) {
  $RenderedSecretsFile = Join-Path $repoRoot $RenderedSecretsFile
}
if (-not $OutputFile) {
  $OutputFile = Join-Path $repoRoot 'generated\compose.env'
}
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
  $OutputFile = Join-Path $repoRoot $OutputFile
}

$baseValues = Parse-DotEnv -Path $baseEnvPath
$secretValues = Parse-DotEnv -Path $RenderedSecretsFile

if (-not $baseValues.Contains('BASE_PATH')) {
  $baseValues['BASE_PATH'] = 'C:\docker'
}
if (-not $baseValues.Contains('INFISICAL_ENV')) {
  $baseValues['INFISICAL_ENV'] = 'prod'
}

foreach ($entry in $secretValues.GetEnumerator()) {
  $baseValues[$entry.Key] = $entry.Value
}

$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$lines = foreach ($key in $baseValues.Keys) {
  "{0}={1}" -f $key, $baseValues[$key]
}
Set-Content -Path $OutputFile -Value $lines -Encoding ascii
Write-Output $OutputFile

