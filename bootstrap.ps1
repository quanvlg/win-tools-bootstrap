#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# Win Tools Bootstrap
# Version: 0.1.0
# ============================================================

$Script:AppName    = 'WinTools'
$Script:Version    = '0.1.0'
$Script:ApiBaseUrl = 'http://192.168.1.104:8000/api/v1'

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


function Invoke-LicenseApi {
    param(
        [Parameter(Mandatory)]
        [string]$LicenseKey
    )

    Write-Log 'Authenticating license...'

    $uri = "$Script:ApiBaseUrl/license/activate"

    Write-Log "API URL: $uri"

    $body = @{
        license_key = $LicenseKey
    } | ConvertTo-Json -Compress

    try {

        $response = Invoke-RestMethod `
            -Uri $uri `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec 15 `
            -ErrorAction Stop

        if (-not $response.success) {
            throw 'License activation failed.'
        }

        if ([string]::IsNullOrWhiteSpace($response.access_token)) {
            throw 'License API did not return an access token.'
        }

        Write-Log 'License authenticated successfully.' 'OK'
        Write-Log "Product: $($response.product)"
        Write-Log "License expires: $($response.expires_at)"

        return $response
    }
    catch {
        Write-Log "API ERROR: $($_.ToString())" 'ERROR'
        throw
    }
}

function Start-Bootstrap {

    Write-Banner

    Initialize-Directories

    Write-Log "Bootstrap version: $Script:Version"

    Test-Windows

    Write-Log 'Reading machine identity...'

    $licenseKey = Read-LicenseKey

    Write-Log 'License key received.'

    $result = Invoke-LicenseApi `
        -LicenseKey $licenseKey

    Write-Log 'License authentication completed.' 'OK'

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