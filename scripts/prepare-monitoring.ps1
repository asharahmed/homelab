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

Write-Host "Using base path: $BasePath"

$targets = @(
  (Join-Path -Path $BasePath -ChildPath "monitoring\\prometheus")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\prometheus\\rules")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\prometheus\\data")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\loki\\data")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\promtail\\positions")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\alertmanager\\data")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\alertmanager\\secrets")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\alertmanager\\templates")
  (Join-Path -Path $BasePath -ChildPath "grafana\\data")
  (Join-Path -Path $BasePath -ChildPath "monitoring\\blackbox")
)

foreach ($dir in $targets) {
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
    Write-Host "Created $dir"
  }
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\prometheus.yml") `
          -Destination (Join-Path $BasePath "monitoring\\prometheus\\prometheus.yml") `
          -Force

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\loki-local-config.yaml") `
          -Destination (Join-Path $BasePath "monitoring\\loki\\loki-local-config.yaml") `
          -Force

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\promtail.yaml") `
          -Destination (Join-Path $BasePath "monitoring\\promtail\\promtail.yaml") `
          -Force

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\alertmanager.yml") `
          -Destination (Join-Path $BasePath "monitoring\\alertmanager\\alertmanager.yml") `
          -Force

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\templates\\*") `
          -Destination (Join-Path $BasePath "monitoring\\alertmanager\\templates") `
          -Force -Recurse

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\rules\\alerts.yml") `
          -Destination (Join-Path $BasePath "monitoring\\prometheus\\rules\\alerts.yml") `
          -Force

Copy-Item -Path (Join-Path $repoRoot "tools\\monitoring\\blackbox.yml") `
          -Destination (Join-Path $BasePath "monitoring\\blackbox\\blackbox.yml") `
          -Force

$routerMetricsToken = Get-EnvValue -Key "ROUTER_METRICS_TOKEN"
$promConfig = Join-Path -Path $BasePath -ChildPath "monitoring\\prometheus\\prometheus.yml"
if ($routerMetricsToken -and (Test-Path -LiteralPath $promConfig)) {
  $content = Get-Content -LiteralPath $promConfig -Raw
  $content = $content.Replace('${ROUTER_METRICS_TOKEN}', $routerMetricsToken)
  Set-Content -LiteralPath $promConfig -Value $content -Encoding utf8
} else {
  Write-Warning "ROUTER_METRICS_TOKEN missing in .env; router scrape will not be rendered."
}

$blackboxToken = Get-EnvValue -Key "BLACKBOX_TOKEN"
$blackboxConfig = Join-Path -Path $BasePath -ChildPath "monitoring\\blackbox\\blackbox.yml"
if ($blackboxToken -and (Test-Path -LiteralPath $blackboxConfig)) {
  $content = Get-Content -LiteralPath $blackboxConfig -Raw
  $content = $content.Replace('__BLACKBOX_TOKEN__', $blackboxToken)
  Set-Content -LiteralPath $blackboxConfig -Value $content -Encoding utf8
} else {
  Write-Warning "BLACKBOX_TOKEN missing in .env; blackbox auth headers will not be rendered."
}

$telegramToken = Get-EnvValue -Key "TELEGRAM_BOT_TOKEN"
if ($telegramToken) {
  $tokenFile = Join-Path -Path $BasePath -ChildPath "monitoring\\alertmanager\\secrets\\telegram_bot_token"
  Set-Content -LiteralPath $tokenFile -Value $telegramToken -NoNewline -Encoding utf8
} else {
  Write-Warning "TELEGRAM_BOT_TOKEN missing in .env; Alertmanager Telegram receiver will fail."
}

$telegramChatId = Get-EnvValue -Key "TELEGRAM_CHAT_ID"
if ($telegramChatId) {
  $amConfig = Join-Path -Path $BasePath -ChildPath "monitoring\\alertmanager\\alertmanager.yml"
  if (Test-Path -LiteralPath $amConfig) {
    $content = Get-Content -LiteralPath $amConfig
    $updated = $false
    for ($i=0; $i -lt $content.Count; $i++) {
      if ($content[$i] -match "YOUR_CHAT_ID") {
        $content[$i] = $content[$i] -replace "YOUR_CHAT_ID", $telegramChatId
        $updated = $true
      }
    }
    if ($updated) {
      Set-Content -LiteralPath $amConfig -Value $content -Encoding utf8
    }
  }
} else {
  Write-Warning "TELEGRAM_CHAT_ID missing in .env; Alertmanager Telegram receiver will fail."
}

Write-Host "Monitoring configuration staged. You can now start the monitoring profile."
