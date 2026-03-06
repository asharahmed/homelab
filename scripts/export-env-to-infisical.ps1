Param(
  [string]$EnvFile = ".env",
  [string]$ProjectId,
  [string]$Environment = "prod",
  [string]$SecretPath,
  [string]$Domain,
  [string]$Token
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

function Resolve-ConfigValue {
  param(
    [string]$ExplicitValue,
    [string[]]$Keys,
    [string]$DefaultValue = $null
  )

  if ($ExplicitValue) {
    return $ExplicitValue
  }

  foreach ($key in $Keys) {
    $value = Get-EnvValue -FilePath $bootstrapEnv -Key $key
    if ($value) {
      return $value
    }

    $value = Get-EnvValue -FilePath $repoEnv -Key $key
    if ($value) {
      return $value
    }
  }

  return $DefaultValue
}

function Invoke-InfisicalHelper {
  param(
    [string[]]$CliArgs,
    [string]$MountSource,
    [string]$MountTarget = "/work"
  )

  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is required to run the Infisical helper container."
  }

  $quotedArgs = $CliArgs | ForEach-Object {
    if ($_ -match '[\s"]') {
      '"' + ($_.Replace('"', '\"')) + '"'
    } else {
      $_
    }
  }

  $commandLine = "npm install -g @infisical/cli >/dev/null 2>&1 && infisical " + ($quotedArgs -join ' ')
  $dockerArgs = @("run", "--rm", "--network", "homelab_default", "-e", "INFISICAL_TOKEN=$Token")

  if ($MountSource) {
    $dockerArgs += @("-v", "$MountSource`:$MountTarget")
  }

  $dockerArgs += @("node:20-alpine", "sh", "-lc", $commandLine)

  & docker @dockerArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Infisical helper command failed."
  }
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$sourceEnv = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
$repoEnv = Join-Path $repoRoot ".env"
$bootstrapEnv = Join-Path $repoRoot ".env.bootstrap.local"

$ProjectId = Resolve-ConfigValue -ExplicitValue $ProjectId -Keys @("INFISICAL_PROJECT_ID")
$Domain = Resolve-ConfigValue -ExplicitValue $Domain -Keys @("INFISICAL_DOCKER_API_URL", "INFISICAL_API_URL", "INFISICAL_SITE_URL") -DefaultValue "http://infisical:8080/api"
$Token = Resolve-ConfigValue -ExplicitValue $Token -Keys @("INFISICAL_MACHINE_TOKEN")
$SecretPath = Resolve-ConfigValue -ExplicitValue $SecretPath -Keys @("INFISICAL_SECRET_PATH") -DefaultValue "/"

if ($Domain -and $Domain -notmatch '/api/?$') {
  $Domain = $Domain.TrimEnd('/') + '/api'
}
if (-not $ProjectId) {
  throw "INFISICAL_PROJECT_ID is required."
}
if (-not $Token) {
  throw "Infisical token is required. Set INFISICAL_TOKEN or INFISICAL_MACHINE_TOKEN."
}
if (-not (Test-Path -LiteralPath $sourceEnv)) {
  throw "Source env file not found: $sourceEnv"
}

$secretPattern = 'TOKEN|PASSWORD|SECRET|KEY|WEBHOOK|SMTP_|CLOUDFLARE|WIREGUARD|AUTH_|BOT_'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("infisical-import-{0}" -f ([guid]::NewGuid().ToString('N')))
$tempFile = Join-Path $tempDir "import.env"

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Get-Content -LiteralPath $sourceEnv | ForEach-Object {
  $line = $_.TrimStart([char]0xFEFF)
  if ($line -match '^\s*#') {
    return
  }

  $parsed = [regex]::Match($line, '^[A-Za-z_][A-Za-z0-9_]*=(.*)$')
  if ($parsed.Success -and $line -match $secretPattern) {
    $value = $parsed.Groups[1].Value.Trim()
    if ($value.Length -gt 0) {
      $line
    }
  }
} | Set-Content -LiteralPath $tempFile -Encoding utf8

if ((Get-Item -LiteralPath $tempFile).Length -eq 0) {
  Remove-Item -LiteralPath $tempDir -Recurse -Force
  throw "No matching secrets found in $sourceEnv"
}

Invoke-InfisicalHelper -MountSource $tempDir -CliArgs @(
  "secrets", "set",
  "--file=/work/import.env",
  "--projectId=$ProjectId",
  "--env=$Environment",
  "--path=$SecretPath",
  "--domain=$Domain",
  "--silent"
)

Remove-Item -LiteralPath $tempDir -Recurse -Force
Write-Host "Selected secrets exported to Infisical project $ProjectId path $SecretPath ($Environment)."


