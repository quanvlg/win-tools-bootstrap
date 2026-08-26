#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# Win Tools Bootstrap
# Version: 0.1.0
# ============================================================

$Script:AppName    = 'WinTools'
$Script:Version    = '0.1.0'
$Script:ApiBaseUrl = 'https://license.example.com/api/v1'

$Script:InstallRoot = Join-Path $env:ProgramData $Script:AppName
$Script:TempRoot    = Join-Path $Script:InstallRoot 'temp'
$Script:LogRoot     = Join-Path $Script:InstallRoot 'logs'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    Write-Host $line

    if ($Script:LogFile) {
        Add-Content -LiteralPath $Script:LogFile -Value $line -Encoding UTF8
    }
}

function Write-Banner {
    Write-Host ''
    Write-Host '========================================'
    Write-Host '              WIN TOOLS'
    Write-Host "              v$Script:Version"
    Write-Host '========================================'
    Write-Host ''
}

function Initialize-Directories {
    foreach ($path in @(
        $Script:InstallRoot,
        $Script:TempRoot,
        $Script:LogRoot
    )) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $Script:LogFile = Join-Path `
        $Script:LogRoot `
        ("bootstrap-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
}

function Test-Windows {
    Write-Log 'Checking operating system...'

    # Compatible with both:
    # - Windows PowerShell 5.1
    # - PowerShell 7+

    if ($env:OS -ne 'Windows_NT') {
        throw 'This bootstrap can only run on Windows.'
    }

    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" 'OK'
    Write-Log 'Windows detected.' 'OK'
}

function Get-MachineGuid {
    $path = 'HKLM:\SOFTWARE\Microsoft\Cryptography'

    try {
        $value = Get-ItemPropertyValue `
            -Path $path `
            -Name 'MachineGuid' `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($value)) {
            throw 'MachineGuid is empty.'
        }

        return $value
    }
    catch {
        throw "Unable to obtain Windows MachineGuid: $($_.Exception.Message)"
    }
}

function Get-DeviceId {
    param(
        [Parameter(Mandatory)]
        [string]$MachineGuid
    )

    $inputBytes = [Text.Encoding]::UTF8.GetBytes(
        "$Script:AppName|$MachineGuid"
    )

    $sha256 = [Security.Cryptography.SHA256]::Create()

    try {
        $hash = $sha256.ComputeHash($inputBytes)
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Read-LicenseKey {
    Write-Host ''
    Write-Host 'License Key'
    Write-Host '-----------'

    $key = Read-Host 'Enter License Key'

    if ([string]::IsNullOrWhiteSpace($key)) {
        throw 'License Key cannot be empty.'
    }

    $key = $key.Trim().ToUpperInvariant()

    # Không ghi key vào log.
    return $key
}

function Get-DeviceInfo {
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId
    )

    return @{
        device_id = $DeviceId
        os        = [Environment]::OSVersion.Version.ToString()
        arch      = if ([Environment]::Is64BitOperatingSystem) {
            'x64'
        }
        else {
            'x86'
        }
        powershell = $PSVersionTable.PSVersion.ToString()
    }
}

function Invoke-LicenseApi {
    param(
        [Parameter(Mandatory)]
        [string]$LicenseKey,

        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo
    )

    Write-Log 'Authenticating license...'

    # ========================================================
    # TODO:
    # Đây sẽ được thay bằng API thật.
    # Tuyệt đối không đưa GitHub token vào bootstrap.
    # ========================================================

    throw 'License API is not configured yet.'
}

function Start-Bootstrap {

    Write-Banner

    Initialize-Directories

    Write-Log "Bootstrap version: $Script:Version"

    Test-Windows

    Write-Log 'Reading machine identity...'

    $machineGuid = Get-MachineGuid
    $deviceId    = Get-DeviceId -MachineGuid $machineGuid

    Write-Log 'Device identity generated.' 'OK'

    $deviceInfo = Get-DeviceInfo -DeviceId $deviceId

    Write-Log 'Device information prepared.' 'OK'

    $licenseKey = Read-LicenseKey

    Write-Log 'License key received.'

    $result = Invoke-LicenseApi `
        -LicenseKey $licenseKey `
        -DeviceInfo $deviceInfo

    return $result
}

try {
    Start-Bootstrap
}
catch {
    Write-Host ''
    Write-Log $_.Exception.Message 'ERROR'
    Write-Host ''
    Write-Host 'Bootstrap failed.' -ForegroundColor Red
    exit 1
}