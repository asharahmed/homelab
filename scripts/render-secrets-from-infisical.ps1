Param(
  [string]$OutputFile,
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

if (-not $OutputFile) {
  $basePath = Get-EnvValue -FilePath $repoEnv -Key "BASE_PATH"
  if (-not $basePath) {
    $basePath = "C:\docker"
  }
  $OutputFile = Join-Path $basePath "runtime-secrets\homelab.env"
}

$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("infisical-export-{0}" -f ([guid]::NewGuid().ToString('N')))
$tempOutput = Join-Path $tempDir "homelab.env"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Invoke-InfisicalHelper -MountSource $tempDir -CliArgs @(
  "export",
  "--format=dotenv",
  "--projectId=$ProjectId",
  "--env=$Environment",
  "--path=$SecretPath",
  "--domain=$Domain",
  "--output-file=/work/homelab.env",
  "--silent"
)

if (-not (Test-Path -LiteralPath $tempOutput)) {
  Remove-Item -LiteralPath $tempDir -Recurse -Force
  throw "Infisical helper did not produce an output file."
}

Copy-Item -LiteralPath $tempOutput -Destination $OutputFile -Force
Remove-Item -LiteralPath $tempDir -Recurse -Force
Write-Host "Rendered Infisical secrets to $OutputFile"
