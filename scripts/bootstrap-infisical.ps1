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

function New-RandomSecret {
  param(
    [ValidateSet('hex16', 'base64_32', 'password')]
    [string]$Kind
  )

  switch ($Kind) {
    'hex16' {
      $bytes = New-Object byte[] 16
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
    }
    'base64_32' {
      $bytes = New-Object byte[] 32
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      return [Convert]::ToBase64String($bytes)
    }
    'password' {
      $bytes = New-Object byte[] 24
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      return [Convert]::ToBase64String($bytes)
    }
  }
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$envFile = Join-Path $repoRoot ".env"
$bootstrapFile = Join-Path $repoRoot ".env.bootstrap.local"

if (-not $BasePath -or $BasePath.Trim() -eq '') {
  $BasePath = Get-EnvValue -FilePath $envFile -Key "BASE_PATH"
}
if (-not $BasePath -or $BasePath.Trim() -eq '') {
  $BasePath = "C:\docker"
}

$siteUrl = Get-EnvValue -FilePath $bootstrapFile -Key "INFISICAL_SITE_URL"
if (-not $siteUrl) {
  $siteUrl = Get-EnvValue -FilePath $envFile -Key "INFISICAL_SITE_URL"
}
if (-not $siteUrl) {
  $siteUrl = "https://secrets.home.aahmed.ca"
}

$encryptionKey = Get-EnvValue -FilePath $bootstrapFile -Key "INFISICAL_ENCRYPTION_KEY"
if (-not $encryptionKey) {
  $encryptionKey = Get-EnvValue -FilePath $envFile -Key "INFISICAL_ENCRYPTION_KEY"
}
if (-not $encryptionKey) {
  $encryptionKey = New-RandomSecret -Kind 'hex16'
}

$authSecret = Get-EnvValue -FilePath $bootstrapFile -Key "INFISICAL_AUTH_SECRET"
if (-not $authSecret) {
  $authSecret = Get-EnvValue -FilePath $envFile -Key "INFISICAL_AUTH_SECRET"
}
if (-not $authSecret) {
  $authSecret = New-RandomSecret -Kind 'base64_32'
}

$postgresPassword = Get-EnvValue -FilePath $bootstrapFile -Key "INFISICAL_POSTGRES_PASSWORD"
if (-not $postgresPassword) {
  $postgresPassword = Get-EnvValue -FilePath $envFile -Key "INFISICAL_POSTGRES_PASSWORD"
}
if (-not $postgresPassword) {
  $postgresPassword = New-RandomSecret -Kind 'password'
}

$redisPassword = Get-EnvValue -FilePath $bootstrapFile -Key "INFISICAL_REDIS_PASSWORD"
if (-not $redisPassword) {
  $redisPassword = Get-EnvValue -FilePath $envFile -Key "INFISICAL_REDIS_PASSWORD"
}
if (-not $redisPassword) {
  $redisPassword = New-RandomSecret -Kind 'password'
}

$targetDirs = @(
  (Join-Path $BasePath "infisical"),
  (Join-Path $BasePath "infisical\bootstrap"),
  (Join-Path $BasePath "infisical\postgres"),
  (Join-Path $BasePath "infisical\redis"),
  (Join-Path $BasePath "infisical\uploads"),
  (Join-Path $BasePath "runtime-secrets")
)

foreach ($dir in $targetDirs) {
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

$runtimeEnvFile = Join-Path $BasePath "infisical\bootstrap\infisical.env"
$dbConnectionUri = "postgresql://infisical:{0}@infisical-postgres:5432/infisical" -f $postgresPassword
$redisUrl = "redis://:{0}@infisical-redis:6379" -f $redisPassword

$content = @(
  "POSTGRES_PASSWORD=$postgresPassword"
  "INFISICAL_POSTGRES_PASSWORD=$postgresPassword"
  "INFISICAL_REDIS_PASSWORD=$redisPassword"
  "ENCRYPTION_KEY=$encryptionKey"
  "AUTH_SECRET=$authSecret"
  "SITE_URL=$siteUrl"
  "DB_CONNECTION_URI=$dbConnectionUri"
  "REDIS_URL=$redisUrl"
  "TELEMETRY_ENABLED=false"
)

Set-Content -LiteralPath $runtimeEnvFile -Value $content -Encoding utf8
Write-Host "Infisical bootstrap env written to $runtimeEnvFile"
Write-Host "Next step: docker compose --profile platform up -d infisical-postgres infisical-redis infisical"
