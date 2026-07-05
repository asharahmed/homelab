#Requires -Version 7
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Create the throwaway Windows 11 VM for Intune enrollment (WS D).

.DESCRIPTION
    Creates a Gen2 Hyper-V VM that satisfies Windows 11 hardware requirements
    (UEFI + Secure Boot + vTPM), builds an answer-file ISO from
    autounattend.xml (password substituted from .env VM_LOCAL_PASSWORD), and
    starts a fully unattended install. The "Press any key to boot from
    CD/DVD" prompt is auto-answered via the Hyper-V keyboard WMI class.

    After install completes the VM auto-logs-on as 'labadmin' once. The only
    manual step left is Entra join + Intune enrollment (Settings > Accounts >
    Access work or school > Connect, sign in as secadmin) - that requires
    interactive MFA and cannot be scripted.

.EXAMPLE
    ./new-intune-vm.ps1 -IsoPath D:\ISOs\win11-enterprise-eval.iso
#>
param(
    [string] $IsoPath   = 'D:\ISOs\win11-enterprise-eval.iso',
    [string] $VmName    = 'Win11-Intune',
    [string] $VmRoot    = 'D:\Hyper-V',
    [int64]  $MemoryMax = 6GB,
    [int64]  $DiskSize  = 64GB,
    [string] $SwitchName = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path "$here/../.."

function Get-EnvValue {
    param([string]$Key)
    $line = Get-Content "$repoRoot/.env" | Where-Object { $_ -match "^\s*$([Regex]::Escape($Key))=(.+)$" } | Select-Object -First 1
    if ($line) { return $Matches[1].Trim() }
    return $null
}

# Builds a UDF ISO from a folder using the in-box IMAPI2 COM API (no ADK needed).
function New-IsoFile {
    param([string]$SourceDir, [string]$TargetIso, [string]$Label = 'UNATTEND')
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3   # ISO9660 + Joliet
    $fsi.VolumeName = $Label
    $fsi.Root.AddTree($SourceDir, $false)
    $image = $fsi.CreateResultImage()
    $stream = $image.ImageStream

    # COM IStream -> file via Adodb is unreliable in pwsh; use ISOWriter helper
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class IsoWriter {
    public static void Write(string path, object comStream) {
        IStream src = (IStream)comStream;
        using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write)) {
            byte[] buf = new byte[2048];
            IntPtr read = Marshal.AllocHGlobal(sizeof(int));
            try {
                int bytesRead;
                do {
                    src.Read(buf, buf.Length, read);
                    bytesRead = Marshal.ReadInt32(read);
                    if (bytesRead > 0) fs.Write(buf, 0, bytesRead);
                } while (bytesRead == buf.Length);
            } finally { Marshal.FreeHGlobal(read); }
        }
    }
}
'@ -ErrorAction SilentlyContinue
    [IsoWriter]::Write($TargetIso, $stream)
    Write-Host "Answer ISO written: $TargetIso" -ForegroundColor Green
}

# --- Preflight ---------------------------------------------------------------
if (-not (Test-Path $IsoPath)) { throw "Install ISO not found: $IsoPath" }
$vmPassword = Get-EnvValue -Key 'VM_LOCAL_PASSWORD'
if (-not $vmPassword) { throw 'VM_LOCAL_PASSWORD missing from .env' }
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) { throw "VM '$VmName' already exists." }

if (-not $SwitchName) {
    $SwitchName = (Get-VMSwitch | Where-Object SwitchType -eq 'External' | Select-Object -First 1).Name
    if (-not $SwitchName) { $SwitchName = 'Default Switch' }
}
Write-Host "VM switch : $SwitchName" -ForegroundColor Cyan

# --- Build answer-file ISO ----------------------------------------------------
$staging = Join-Path $env:TEMP "unattend-$VmName"
New-Item -ItemType Directory -Path $staging -Force | Out-Null
(Get-Content "$here/autounattend.xml" -Raw).Replace('{{VM_LOCAL_PASSWORD}}', $vmPassword) |
    Set-Content "$staging/autounattend.xml" -Encoding utf8
$answerIso = Join-Path $VmRoot "$VmName-unattend.iso"
New-Item -ItemType Directory -Path $VmRoot -Force | Out-Null
New-IsoFile -SourceDir $staging -TargetIso $answerIso
Remove-Item $staging -Recurse -Force

# --- Create VM -----------------------------------------------------------------
$vhdPath = Join-Path $VmRoot "$VmName.vhdx"
$vm = New-VM -Name $VmName -Generation 2 -MemoryStartupBytes 4GB `
    -NewVHDPath $vhdPath -NewVHDSizeBytes $DiskSize -SwitchName $SwitchName -Path $VmRoot
Set-VM -Name $VmName -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes $MemoryMax -AutomaticCheckpointsEnabled $false

# Win11 requirements: Secure Boot (MS template) + vTPM
Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
$kp = New-HgsGuardian -Name "$VmName-guardian" -GenerateCertificates -ErrorAction SilentlyContinue
if (-not $kp) { $kp = Get-HgsGuardian -Name "$VmName-guardian" }
Set-VMKeyProtector -VMName $VmName -KeyProtector (New-HgsKeyProtector -Owner $kp -AllowUntrustedRoot).RawData
Enable-VMTPM -VMName $VmName

# Attach install ISO + answer ISO, boot from DVD
$dvd1 = Add-VMDvdDrive -VMName $VmName -Path $IsoPath -Passthru
Add-VMDvdDrive -VMName $VmName -Path $answerIso
Set-VMFirmware -VMName $VmName -FirstBootDevice $dvd1

Start-VM -Name $VmName
Write-Host "VM '$VmName' started." -ForegroundColor Green

# --- Auto-press a key for the 'Press any key to boot from CD/DVD' prompt ------
Write-Host 'Sending keystrokes for the DVD boot prompt...' -ForegroundColor Yellow
$vmWmi = Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName Msvm_ComputerSystem -Filter "ElementName='$VmName'"
$kb = Get-CimAssociatedInstance -InputObject $vmWmi -ResultClassName Msvm_Keyboard
1..20 | ForEach-Object {
    Invoke-CimMethod -InputObject $kb -MethodName 'TypeKey' -Arguments @{ keyCode = [uint32]13 } | Out-Null
    Start-Sleep -Milliseconds 500
}
Write-Host @'

Unattended install is running (~15-30 min). Watch with: vmconnect localhost Win11-Intune
When it lands on the desktop (auto-logon as labadmin):
  1. Settings > Accounts > Access work or school > Connect
  2. Sign in as secadmin@asharasharahmed.onmicrosoft.com (MFA required)
  3. Device enrolls in Intune automatically (MDM auto-enrollment)
'@ -ForegroundColor Cyan
