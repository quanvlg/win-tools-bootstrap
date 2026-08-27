#requires -Version 5.1

[CmdletBinding()]
param()

# ============================================================
# WIN TOOLS - AUTO ELEVATION
# PowerShell 5.1 compatible
# ============================================================

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsAdministrator)) {

    Write-Host ""
    Write-Host "Administrator privileges are required." -ForegroundColor Yellow
    Write-Host "Requesting elevation..." -ForegroundColor Yellow
    Write-Host ""

    try {
        $scriptPath = $MyInvocation.MyCommand.Definition

        if (-not $scriptPath) {
            throw "Unable to determine bootstrap script path."
        }

        $arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit  -File `"$scriptPath`""

        Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $arguments `
            -Verb RunAs

        exit 0
    }
    catch {
        Write-Host ""
        Write-Host "Failed to request Administrator privileges." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

$ErrorActionPreference = "Stop"

$script:BootstrapVersion = "0.2.0"

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------

$script:Config = @{
    ApiBaseUrl = "http://192.168.1.104:8000"

    ActivateEndpoint = "/api/v1/license/activate"
    LatestEndpoint   = "/api/v1/package/latest"
    DownloadEndpoint = "/api/v1/package/download"

    Product = "win-tools"

    InstallRoot = Join-Path $env:ProgramData "WinTools"
    CacheRoot   = Join-Path $env:ProgramData "WinTools\cache"
    PackageRoot = Join-Path $env:ProgramData "WinTools\packages"

    ApiTimeoutSec = 60
    DownloadTimeoutSec = 300

    # STEP A:
    # Signature chưa bắt buộc.
    # Sẽ bật ở STEP B.
    RequireSignature = $false
}

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------

$script:LogDirectory = Join-Path `
    $script:Config.InstallRoot `
    "logs"

$script:LogFile = Join-Path `
    $script:LogDirectory `
    "bootstrap.log"


function Initialize-Environment {

    New-Item `
        -ItemType Directory `
        -Path $script:Config.InstallRoot `
        -Force | Out-Null

    New-Item `
        -ItemType Directory `
        -Path $script:Config.CacheRoot `
        -Force | Out-Null

    New-Item `
        -ItemType Directory `
        -Path $script:Config.PackageRoot `
        -Force | Out-Null

    New-Item `
        -ItemType Directory `
        -Path $script:LogDirectory `
        -Force | Out-Null
}


function Write-Log {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet(
            "INFO",
            "OK",
            "WARN",
            "ERROR"
        )]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $line = "[{0}] [{1}] {2}" -f `
        $timestamp,
        $Level,
        $Message

    Write-Host $line

    try {
        Add-Content `
            -Path $script:LogFile `
            -Value $line `
            -Encoding UTF8
    }
    catch {
        # Logging failure must not crash bootstrap.
    }
}


# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------

function Show-Banner {

    Write-Host ""
    Write-Host "========================================"
    Write-Host "              WIN TOOLS"
    Write-Host "              v$($script:BootstrapVersion)"
    Write-Host "========================================"
    Write-Host ""
}


# ------------------------------------------------------------------------------
# SYSTEM CHECK
# ------------------------------------------------------------------------------

function Test-Windows {

    Write-Log "Checking operating system..."

    # Compatible with Windows PowerShell 5.1.
    # Do NOT use $IsWindows because that variable does not exist in PS 5.1.

    if (-not [Environment]::OSVersion.Platform -eq `
        [System.PlatformID]::Win32NT) {

        throw "This bootstrap can only run on Windows."
    }

    Write-Log `
        "PowerShell version: $($PSVersionTable.PSVersion)" `
        "OK"

    Write-Log "Windows detected." "OK"
}


function Test-Administrator {

    Write-Log "Checking administrator privileges..."

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object `
        Security.Principal.WindowsPrincipal($identity)

    $isAdmin = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdmin) {
        throw "Administrator privileges are required."
    }

    Write-Log "Administrator privileges confirmed." "OK"
}


# ------------------------------------------------------------------------------
# TLS
# ------------------------------------------------------------------------------

function Initialize-Tls {

    Write-Log "Initializing secure TLS settings..."

    try {

        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12

        Write-Log "TLS 1.2 enabled." "OK"
    }
    catch {

        Write-Log `
            "Unable to explicitly configure TLS 1.2: $($_.Exception.Message)" `
            "WARN"
    }
}


# ------------------------------------------------------------------------------
# DEVICE INFORMATION
# ------------------------------------------------------------------------------

function Get-DeviceInformation {

    Write-Log "Reading machine identity..."

    $computerName = $env:COMPUTERNAME

    $machineGuid = $null

    try {

        $machineGuid = (
            Get-ItemProperty `
                -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" `
                -Name "MachineGuid" `
                -ErrorAction Stop
        ).MachineGuid
    }
    catch {

        Write-Log `
            "MachineGuid unavailable." `
            "WARN"
    }

    $deviceId = $machineGuid

    if ([string]::IsNullOrWhiteSpace($deviceId)) {

        $deviceId = $computerName
    }

    Write-Log "Device identity generated." "OK"

    return @{
        device_id = $deviceId
        hostname  = $computerName
    }
}


# ------------------------------------------------------------------------------
# HTTP
# ------------------------------------------------------------------------------

function Invoke-ApiRequest {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST")]
        [string]$Method,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [int]$TimeoutSec = 60,

        [int]$MaxRetries = 3
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {

        try {

            $params = @{
                Uri         = $Uri
                Method      = $Method
                TimeoutSec  = $TimeoutSec
                ErrorAction = "Stop"
                UseBasicParsing = $true
            }

            if ($Headers) {
                $params.Headers = $Headers
            }

            if ($null -ne $Body) {

                $params.ContentType = "application/json"

                $params.Body = (
                    $Body | ConvertTo-Json -Depth 10
                )
            }

            return Invoke-RestMethod @params
        }
        catch {

            $message = $_.Exception.Message

            Write-Log `
                "API request failed (attempt $attempt/$MaxRetries): $message" `
                "WARN"

            if ($attempt -ge $MaxRetries) {

                throw
            }

            Start-Sleep -Seconds (
                [Math]::Min(2 * $attempt, 5)
            )
        }
    }
}


# ------------------------------------------------------------------------------
# LICENSE
# ------------------------------------------------------------------------------

function Read-LicenseKey {

    Write-Host ""
    Write-Host "License Key"
    Write-Host "-----------"

    $licenseKey = Read-Host "Enter License Key"

    if ([string]::IsNullOrWhiteSpace($licenseKey)) {

        throw "License key cannot be empty."
    }

    Write-Log "License key received."

    return $licenseKey.Trim()
}


function Invoke-LicenseActivation {

    param(
        [Parameter(Mandatory = $true)]
        [string]$LicenseKey,

        [Parameter(Mandatory = $true)]
        [hashtable]$Device
    )

    Write-Log "Authenticating license..."

    $uri = $script:Config.ApiBaseUrl +
        $script:Config.ActivateEndpoint

    $body = @{
        license_key = $LicenseKey
        device_id   = $Device.device_id
        hostname    = $Device.hostname
    }

    try {

        $response = Invoke-ApiRequest `
            -Uri $uri `
            -Method POST `
            -Body $body `
            -TimeoutSec $script:Config.ApiTimeoutSec

        if (-not $response.success) {

            throw "License activation failed."
        }

        if ([string]::IsNullOrWhiteSpace(
            $response.access_token
        )) {

            throw "API returned an empty access token."
        }

        Write-Log "License authenticated successfully." "OK"

        if ($response.expires_at) {

            Write-Log `
                "License expires at: $($response.expires_at)" `
                "INFO"
        }

        return $response
    }
    catch {

        Write-Log `
            "License authentication failed: $($_.Exception.Message)" `
            "ERROR"

        throw
    }
}


# ------------------------------------------------------------------------------
# PACKAGE METADATA
# ------------------------------------------------------------------------------

function Get-LatestPackage {

    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    Write-Log "Checking latest package..."

    $uri = $script:Config.ApiBaseUrl +
        $script:Config.LatestEndpoint

    $headers = @{
        Authorization = "Bearer $AccessToken"
        Accept        = "application/json"
    }

    try {

        $package = Invoke-ApiRequest `
            -Uri $uri `
            -Method GET `
            -Headers $headers `
            -TimeoutSec $script:Config.ApiTimeoutSec

        if (-not $package) {

            throw "Package metadata is empty."
        }

        if ([string]::IsNullOrWhiteSpace(
            $package.version
        )) {

            throw "Package version is missing."
        }

        if ([string]::IsNullOrWhiteSpace(
            $package.filename
        )) {

            throw "Package filename is missing."
        }

        if ([string]::IsNullOrWhiteSpace(
            $package.sha256
        )) {

            throw "Package SHA256 is missing."
        }

        Write-Log `
            "Latest package: $($package.filename)" `
            "OK"

        Write-Log `
            "Package version: $($package.version)" `
            "INFO"

        return $package
    }
    catch {

        Write-Log `
            "Unable to get package metadata: $($_.Exception.Message)" `
            "ERROR"

        throw
    }
}


# ------------------------------------------------------------------------------
# PACKAGE DOWNLOAD
# ------------------------------------------------------------------------------

function Download-Package {

    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$Filename
    )

    $safeFilename = [IO.Path]::GetFileName($Filename)

    if ($safeFilename -ne $Filename) {

        throw "Invalid package filename."
    }

    $destination = Join-Path `
        $script:Config.CacheRoot `
        $safeFilename

    $uri = $script:Config.ApiBaseUrl +
        $script:Config.DownloadEndpoint

    Write-Log "Downloading package..."
    Write-Log "Filename: $safeFilename"

    $headers = @{
        Authorization = "Bearer $AccessToken"
    }

    try {

        Invoke-WebRequest `
            -Uri $uri `
            -Headers $headers `
            -Method GET `
            -OutFile $destination `
            -UseBasicParsing `
            -TimeoutSec $script:Config.DownloadTimeoutSec `
            -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $destination)) {

            throw "Downloaded package does not exist."
        }

        $file = Get-Item -LiteralPath $destination

        if ($file.Length -le 0) {

            throw "Downloaded package is empty."
        }

        Write-Log `
            "Package downloaded: $($file.Length) bytes" `
            "OK"

        return $destination
    }
    catch {

        Write-Log `
            "Package download failed: $($_.Exception.Message)" `
            "ERROR"

        Remove-Item `
            -LiteralPath $destination `
            -Force `
            -ErrorAction SilentlyContinue

        throw
    }
}


# ------------------------------------------------------------------------------
# SHA256
# ------------------------------------------------------------------------------

function Get-FileSha256 {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {

        throw "Package file not found."
    }

    $hash = Get-FileHash `
        -LiteralPath $Path `
        -Algorithm SHA256

    return $hash.Hash.ToLowerInvariant()
}


function Test-PackageSha256 {

    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedHash
    )

    Write-Log "Verifying package SHA256..."

    $actualHash = Get-FileSha256 `
        -Path $FilePath

    $expected = $ExpectedHash.Trim().ToLowerInvariant()

    Write-Log "Expected SHA256: $expected"
    Write-Log "Actual SHA256:   $actualHash"

    if ($actualHash -ne $expected) {

        Write-Log `
            "SHA256 verification FAILED." `
            "ERROR"

        return $false
    }

    Write-Log `
        "SHA256 verification OK." `
        "OK"

    return $true
}


# ------------------------------------------------------------------------------
# PACKAGE EXTRACTION
# ------------------------------------------------------------------------------

function Expand-Package {

    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $safeVersion = $Version -replace '[^a-zA-Z0-9._-]', '_'

    $stagingRoot = Join-Path `
        $script:Config.PackageRoot `
        ".staging-$safeVersion"

    $packageRoot = Join-Path `
        $script:Config.PackageRoot `
        $safeVersion

    Write-Log "Preparing package staging..."

    if (Test-Path -LiteralPath $stagingRoot) {

        Remove-Item `
            -LiteralPath $stagingRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    New-Item `
        -ItemType Directory `
        -Path $stagingRoot `
        -Force | Out-Null

    Write-Log "Extracting package..."

    try {

        Expand-Archive `
            -LiteralPath $ZipPath `
            -DestinationPath $stagingRoot `
            -Force `
            -ErrorAction Stop

        Write-Log "Package extracted." "OK"

        return @{
            Staging = $stagingRoot
            Final   = $packageRoot
        }
    }
    catch {

        Remove-Item `
            -LiteralPath $stagingRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        throw
    }
}


# ------------------------------------------------------------------------------
# PACKAGE VALIDATION
# ------------------------------------------------------------------------------

function Test-PackageStructure {

    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageDirectory
    )

    Write-Log "Validating package structure..."

    $entrypoint = Join-Path `
        $PackageDirectory `
        "install.ps1"

    if (-not (Test-Path -LiteralPath $entrypoint)) {

        throw "Package entrypoint install.ps1 not found."
    }

    $manifest = Join-Path `
        $PackageDirectory `
        "manifest.json"

    if (-not (Test-Path -LiteralPath $manifest)) {

        throw "Package manifest.json not found."
    }

    Write-Log "Package structure valid." "OK"

    return $true
}


# ------------------------------------------------------------------------------
# PACKAGE COMMIT
# ------------------------------------------------------------------------------

function Install-Package {

    param(
        [Parameter(Mandatory = $true)]
        [string]$StagingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$FinalDirectory
    )

    Write-Log "Committing package..."

    if (Test-Path -LiteralPath $FinalDirectory) {

        Write-Log `
            "Existing package detected. Replacing it..." `
            "INFO"

        Remove-Item `
            -LiteralPath $FinalDirectory `
            -Recurse `
            -Force `
            -ErrorAction Stop
    }

    Move-Item `
        -LiteralPath $StagingDirectory `
        -Destination $FinalDirectory `
        -Force `
        -ErrorAction Stop

    Write-Log "Package installed." "OK"
}


# ------------------------------------------------------------------------------
# RUN PACKAGE
# ------------------------------------------------------------------------------

function Invoke-Package {

    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageDirectory
    )

    $entrypoint = Join-Path `
        $PackageDirectory `
        "install.ps1"

    if (-not (Test-Path -LiteralPath $entrypoint)) {

        throw "install.ps1 not found."
    }

    Write-Log "Running package entrypoint..."
    Write-Log "Entrypoint: $entrypoint"

    try {

        & powershell.exe `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $entrypoint

        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {

            throw `
                "Package returned exit code $exitCode."
        }

        Write-Log `
            "Package execution completed successfully." `
            "OK"
    }
    catch {

        Write-Log `
            "Package execution failed: $($_.Exception.Message)" `
            "ERROR"

        throw
    }
}


# ------------------------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------------------------

function Remove-TemporaryFiles {

    param(
        [string]$PackageFile,
        [string]$StagingDirectory
    )

    Write-Log "Cleaning temporary files..."

    if ($PackageFile -and
        (Test-Path -LiteralPath $PackageFile)) {

        Remove-Item `
            -LiteralPath $PackageFile `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($StagingDirectory -and
        (Test-Path -LiteralPath $StagingDirectory)) {

        Remove-Item `
            -LiteralPath $StagingDirectory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-Log "Cleanup completed." "OK"
}


# ==============================================================================
# MAIN
# ==============================================================================

$packageFile = $null
$stagingDirectory = $null

try {

    Initialize-Environment

    Clear-Host

    Show-Banner

    Write-Log `
        "Bootstrap version: $($script:BootstrapVersion)"

    # --------------------------------------------------------------------------
    # 1. SYSTEM
    # --------------------------------------------------------------------------

    Test-Windows

    Test-Administrator

    Initialize-Tls

    # --------------------------------------------------------------------------
    # 2. DEVICE
    # --------------------------------------------------------------------------

    Write-Log "Reading machine identity..."

    $device = Get-DeviceInformation

    # --------------------------------------------------------------------------
    # 3. LICENSE
    # --------------------------------------------------------------------------

    $licenseKey = Read-LicenseKey

    $auth = Invoke-LicenseActivation `
        -LicenseKey $licenseKey `
        -Device $device

    $accessToken = $auth.access_token

    # --------------------------------------------------------------------------
    # 4. PACKAGE METADATA
    # --------------------------------------------------------------------------

    $package = Get-LatestPackage `
        -AccessToken $accessToken

    # --------------------------------------------------------------------------
    # 5. DOWNLOAD
    # --------------------------------------------------------------------------

    $packageFile = Download-Package `
        -AccessToken $accessToken `
        -Filename $package.filename

    # --------------------------------------------------------------------------
    # 6. SHA256
    # --------------------------------------------------------------------------

    $hashValid = Test-PackageSha256 `
        -FilePath $packageFile `
        -ExpectedHash $package.sha256

    if (-not $hashValid) {

        throw "Package integrity check failed."
    }

    # --------------------------------------------------------------------------
    # 7. SIGNATURE
    # --------------------------------------------------------------------------

    if ($script:Config.RequireSignature) {

        throw `
            "Signature verification is required but not implemented in Step A."
    }
    else {

        if ($package.signature) {

            Write-Log `
                "Package signature received but verification is deferred to Step B." `
                "WARN"
        }
        else {

            Write-Log `
                "Package signature is not enabled in Step A." `
                "WARN"
        }
    }

    # --------------------------------------------------------------------------
    # 8. EXTRACT
    # --------------------------------------------------------------------------

    $paths = Expand-Package `
        -ZipPath $packageFile `
        -Version $package.version

    $stagingDirectory = $paths.Staging

    # --------------------------------------------------------------------------
    # 9. VALIDATE
    # --------------------------------------------------------------------------

    Test-PackageStructure `
        -PackageDirectory $stagingDirectory

    # --------------------------------------------------------------------------
    # 10. INSTALL
    # --------------------------------------------------------------------------

    Install-Package `
        -StagingDirectory $stagingDirectory `
        -FinalDirectory $paths.Final

    $stagingDirectory = $null

    # --------------------------------------------------------------------------
    # 11. EXECUTE
    # --------------------------------------------------------------------------

    Invoke-Package `
        -PackageDirectory $paths.Final

    # --------------------------------------------------------------------------
    # SUCCESS
    # --------------------------------------------------------------------------

    Remove-TemporaryFiles `
        -PackageFile $packageFile

    $packageFile = $null

    Write-Host ""
    Write-Host "========================================"
    Write-Host "       WIN TOOLS SUCCESS"
    Write-Host "========================================"
    Write-Host ""

    Write-Log `
        "Bootstrap completed successfully." `
        "OK"

    exit 0
}
catch {

    Write-Log `
        "Bootstrap failed: $($_.Exception.Message)" `
        "ERROR"

    Remove-TemporaryFiles `
        -PackageFile $packageFile `
        -StagingDirectory $stagingDirectory

    Write-Host ""
    Write-Host "Bootstrap failed."
    Write-Host ""

    exit 1
}