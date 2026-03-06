param(
    [string]$ComposeFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docker-compose.yml'),
    [string]$ManagerContainerName = 'wazuh.manager',
    [string]$ManagerAddress = '192.168.1.50',
    [int]$ManagerPort = 15140,
    [string]$RegistrationServer = '192.168.1.50',
    [int]$RegistrationPort = 15150,
    [string]$AgentName = $env:COMPUTERNAME,
    [string]$AgentGroup = 'default',
    [string]$RegistrationPassword = '',
    [string]$RegistrationCaPath = '',
    [ValidateSet('TCP', 'UDP')]
    [string]$Protocol = 'TCP',
    [string]$DownloadDir = "$env:TEMP",
    [switch]$ReinstallIfVersionMismatch
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in an elevated PowerShell session (Administrator).'
    }
}

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$EnvFile,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not (Test-Path -LiteralPath $EnvFile)) {
        return $null
    }

    $escapedKey = [Regex]::Escape($Key)
    $match = Select-String -Path $EnvFile -Pattern "^${escapedKey}=(.*)$" | Select-Object -First 1
    if ($match) {
        return $match.Matches[0].Groups[1].Value.Trim()
    }

    return $null
}

function Get-ManagerVersionFromDocker {
    param([Parameter(Mandatory = $true)][string]$ContainerName)

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $null
    }

    $imageRef = (docker inspect --format '{{.Config.Image}}' $ContainerName 2>$null | Out-String).Trim()
    if (-not $imageRef) {
        return $null
    }

    if ($imageRef -notmatch '^wazuh/wazuh-manager:(.+)$') {
        return $null
    }

    return $Matches[1]
}

function Get-ManagerVersionFromCompose {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $lines = Get-Content -LiteralPath $Path
    $inManager = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*wazuh\.manager:\s*$') {
            $inManager = $true
            continue
        }

        if ($inManager -and $line -match '^\s{2}[a-zA-Z0-9_.-]+:\s*$' -and $line -notmatch '^\s*image:\s*') {
            $inManager = $false
        }

        if ($inManager -and $line -match '^\s*image:\s*wazuh/wazuh-manager:(?<version>[^\s#]+)') {
            return $Matches['version']
        }
    }

    return $null
}

function Resolve-AgentVersion {
    param([Parameter(Mandatory = $true)][string]$ManagerVersion)

    if ($ManagerVersion -match '^\d+\.\d+\.\d+-\d+$') {
        return $ManagerVersion
    }

    if ($ManagerVersion -match '^\d+\.\d+\.\d+$') {
        return "$ManagerVersion-1"
    }

    throw "Unsupported manager version format: '$ManagerVersion'"
}

function Test-AgentPackageAvailable {
    param([Parameter(Mandatory = $true)][string]$Version)

    $url = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version.msi"
    try {
        Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing | Out-Null
        return $true
    } catch {
        return $false
    }
}

try {
    Assert-Admin

    if (-not $RegistrationServer -or $RegistrationServer.Trim() -eq '') {
        $RegistrationServer = $ManagerAddress
    }

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $envFile = Join-Path $repoRoot '.env'

    if (-not $RegistrationPassword -or $RegistrationPassword.Trim() -eq '') {
        foreach ($key in @('WAZUH_REGISTRATION_PASSWORD', 'WAZUH_AGENT_REGISTRATION_PASSWORD')) {
            $candidate = Get-EnvValue -EnvFile $envFile -Key $key
            if ($candidate -and $candidate.Trim() -ne '') {
                $RegistrationPassword = $candidate
                Write-Info "Using registration password from .env key '$key'."
                break
            }
        }
    }

    if (-not $RegistrationCaPath -or $RegistrationCaPath.Trim() -eq '') {
        foreach ($path in @(
            'C:\docker\wazuh\config\wazuh_indexer_ssl_certs\root-ca-manager.pem',
            'C:\docker\wazuh\config\wazuh_indexer_ssl_certs\root-ca.pem'
        )) {
            if (Test-Path -LiteralPath $path) {
                $RegistrationCaPath = $path
                Write-Info "Using registration CA: $RegistrationCaPath"
                break
            }
        }
    }

    $managerVersion = Get-ManagerVersionFromDocker -ContainerName $ManagerContainerName
    if (-not $managerVersion) {
        $managerVersion = Get-ManagerVersionFromCompose -Path $ComposeFile
    }
    if (-not $managerVersion) {
        throw "Could not determine Wazuh manager version from Docker container '$ManagerContainerName' or compose file '$ComposeFile'."
    }

    $agentVersion = Resolve-AgentVersion -ManagerVersion $managerVersion
    if (-not (Test-AgentPackageAvailable -Version $agentVersion)) {
        throw "Agent package not found for version '$agentVersion'. Set an explicit version in scripts/install-wazuh-agent-windows.ps1 or verify manager version '$managerVersion'."
    }

    Write-Info "Manager version: $managerVersion"
    Write-Info "Agent version: $agentVersion"
    Write-Info "Manager endpoint: $ManagerAddress`:$ManagerPort"
    Write-Info "Enrollment endpoint: $RegistrationServer`:$RegistrationPort"

    $installerScript = Join-Path $PSScriptRoot 'install-wazuh-agent-windows.ps1'
    if (-not (Test-Path -LiteralPath $installerScript)) {
        throw "Installer script not found: $installerScript"
    }

    $installParams = @{
        Version = $agentVersion
        ManagerAddress = $ManagerAddress
        ManagerPort = $ManagerPort
        RegistrationServer = $RegistrationServer
        RegistrationPort = $RegistrationPort
        AgentName = $AgentName
        AgentGroup = $AgentGroup
        Protocol = $Protocol
        DownloadDir = $DownloadDir
    }

    if ($RegistrationPassword -and $RegistrationPassword.Trim() -ne '') {
        $installParams['RegistrationPassword'] = $RegistrationPassword
    }

    if ($RegistrationCaPath -and $RegistrationCaPath.Trim() -ne '') {
        $installParams['RegistrationCaPath'] = $RegistrationCaPath
    }

    if ($ReinstallIfVersionMismatch) {
        $installParams['ReinstallIfVersionMismatch'] = $true
    }

    & $installerScript @installParams

    Write-Success 'Automatic Wazuh agent install + enrollment completed.'
} finally {
    # no cleanup
}
