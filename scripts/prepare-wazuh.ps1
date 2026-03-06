Param(
  [string]$BasePath
)

$ErrorActionPreference = 'Stop'

function Get-EnvValue {
  param([string]$Key)
  $envFile = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath "..\\.env"
  if (-not (Test-Path $envFile)) { return $null }
  $escapedKey = [Regex]::Escape($Key)
  $match = Select-String -Path $envFile -Pattern "^${escapedKey}=(.*)$" | Select-Object -First 1
  if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
  return $null
}

if (-not $BasePath -or $BasePath.Trim() -eq '') {
  $BasePath = Get-EnvValue -Key "BASE_PATH"
}
if (-not $BasePath -or $BasePath.Trim() -eq '') {
  $BasePath = "C:\\docker"
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$templatePath = Join-Path $repoRoot "tools\\wazuh\\wazuh_cluster\\wazuh_manager.conf"
$targetDir = Join-Path $BasePath "wazuh\\config\\wazuh_cluster"
$targetPath = Join-Path $targetDir "wazuh_manager.conf"

if (-not (Test-Path $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

$replacements = @{
  '{{WAZUH_SYSLOG_ALLOWED_IPS}}' = (Get-EnvValue -Key 'WAZUH_SYSLOG_ALLOWED_IPS')
  '{{CROWDSEC_LAPI_POLL_KEY}}' = (Get-EnvValue -Key 'CROWDSEC_LAPI_POLL_KEY')
  '{{DISCORD_WEBHOOK_URL}}' = (Get-EnvValue -Key 'DISCORD_WEBHOOK_URL')
  '{{ABUSEIPDB_API_KEY}}' = (Get-EnvValue -Key 'ABUSEIPDB_API_KEY')
  '{{SHUFFLE_WEBHOOK_URL}}' = (Get-EnvValue -Key 'SHUFFLE_WEBHOOK_URL')
}

$missing = $replacements.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) } | Select-Object -ExpandProperty Key
if ($missing) {
  throw "Missing required Wazuh values in .env: $($missing -join ', ')"
}

$content = Get-Content -LiteralPath $templatePath -Raw
foreach ($replacement in $replacements.GetEnumerator()) {
  $content = $content.Replace($replacement.Key, $replacement.Value)
}

Set-Content -LiteralPath $targetPath -Value $content -Encoding utf8
Write-Host "Wazuh configuration staged to $targetPath"
