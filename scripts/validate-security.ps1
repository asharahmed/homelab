Param(
  [string]$RepoPath = "."
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
  throw "Trivy is not installed or not on PATH."
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$target = Join-Path $repoRoot $RepoPath
$trivyConfig = Join-Path $repoRoot "tools\security\trivy\trivy.yaml"
$trivyIgnore = Join-Path $repoRoot "tools\security\trivy\ignore.yaml"
$skipDirs = @('.git', '.tmp', 'node_modules', 'generated', 'runtime-secrets')
$skipFiles = @('.env', '.env.bootstrap.local')

if (-not (Test-Path -LiteralPath $target)) {
  throw "Target path not found: $target"
}

$commonArgs = @('--config', $trivyConfig, '--ignorefile', $trivyIgnore)
foreach ($dir in $skipDirs) {
  $commonArgs += @('--skip-dirs', $dir)
}
foreach ($file in $skipFiles) {
  $commonArgs += @('--skip-files', $file)
}

& trivy fs @commonArgs --scanners secret,misconfig $target
& trivy config @commonArgs $target
