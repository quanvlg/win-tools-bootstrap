#requires -Version 5.1

# ============================================================
# REQUIRE ADMINISTRATOR
# ============================================================

function Test-IsAdministrator {

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object `
        Security.Principal.WindowsPrincipal `
        $identity

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}


if (-not (Test-IsAdministrator)) {

    Write-Host ""
    Write-Host "[INFO] Administrator privileges are required."
    Write-Host "[INFO] Requesting elevation..."
    Write-Host ""

    $bootstrapUrl = "https://raw.githubusercontent.com/quanvlg/win-tools-bootstrap/main/bootstrap.ps1"

    $elevatedCommand = @"
`$ErrorActionPreference = 'Stop'
irm '$bootstrapUrl' | iex
"@

    Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-Command", $elevatedCommand
        )

    exit 0
}

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

# ============================================================
# TEMPORARY PACKAGE WORKSPACE
# ============================================================

$PackageWorkspace = $null
$PackageZipPath    = $null
$PackageExtractDir = $null

function New-PackageWorkspace {

    $tempBase = Join-Path $env:TEMP "WinTools"

    if (-not (Test-Path -LiteralPath $tempBase)) {
        New-Item `
            -ItemType Directory `
            -Path $tempBase `
            -Force `
            | Out-Null
    }

    $workspaceId = [Guid]::NewGuid().ToString("N")

    $workspace = Join-Path `
        $tempBase `
        $workspaceId

    $zipPath = Join-Path `
        $workspace `
        "package.zip"

    $extractDir = Join-Path `
        $workspace `
        "package"

    New-Item `
        -ItemType Directory `
        -Path $workspace `
        -Force `
        | Out-Null

    $script:PackageWorkspace = $workspace
    $script:PackageZipPath = $zipPath
    $script:PackageExtractDir = $extractDir

    Write-Log "Temporary workspace: $workspace" -Level INFO

    return $workspace
}
# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------

$script:Config = @{
    ApiBaseUrl = "http://rdp.signtax.vn:8008"

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
    RequireSignature = $true
    SigningPublicKeyXml  = @"
<RSAKeyValue>
<Modulus>rcrfHmj/wQHWj9hQpufnE5ySHoHVepHuFeO/K2PoZYq+Vn7WigTOfI74U0Kk6Cky/33QGsisfObQD9RB79KlAA194bqWPN1J+cXtEC0ceU/i95laaioxI8wW/wmbjy8Oogy2ENDq5achOimU2uU+3drqRgzXlX6jcZRUKeNZ3AI0BlGJ8qwtVsnJxUbGzSs7PWfHJU3wB/ngSYguatFKpmcijjE6FZP4sZCfuq4DM2gJDqgPc5L814r5fRFjBhIyeBAXVv/wIh/nVQLMbgeYIKv2cf4iREs8CNAIes4wtcmpKVjdJZWWJX7Hb6U4MBImQZjvf/mq5hc7dgC2LOoGI0VMZe3tQDNr+JNlPhTJEggYmbLpbcJXvGLYf4IOqcmEvJ/AMDQMu56T7dejGWYp87x89WSWY1HRJU2f2N/WM0EaGw1aA9072tpTYuYf+ieTp6Kqv3veqizzpdKCMm2JOfxuxv/F8NtWNuAw8DBFLmHfjkr5QQa8LgvOb4ObnewfpI1ZS2FHHR/Z/TmdAkqdooqeNVGSf8VNH//3tzrfH5Xv1JJ626FAot8Q6QkOLbCs8Xe20A6IPeWWMLH8Cmv1PRD5VW6asz72xQC3GKyU3wf3cnaUc4x6HwwATtSb48EHzml1LAn3ok60BZVjcqBFs/gG+b48xeo4MfqVEKfgvRc=</Modulus>
<Exponent>AQAB</Exponent>
</RSAKeyValue>
"@
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

    # ========================================
    # Validate filename
    # ========================================

    $safeFilename = [System.IO.Path]::GetFileName($Filename)

    if ([string]::IsNullOrWhiteSpace($safeFilename)) {
        throw "Invalid package filename."
    }

    if ($safeFilename -ne $Filename) {
        throw "Invalid package filename."
    }

    # ========================================
    # Create temporary WinTools directory
    # ========================================

    try {

        $tempRoot = Join-Path $env:TEMP "WinTools"

        if (-not (Test-Path -LiteralPath $tempRoot)) {

            New-Item `
                -ItemType Directory `
                -Path $tempRoot `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        # Random staging directory for this execution
        $stagingRoot = Join-Path `
            $tempRoot `
            ([guid]::NewGuid().ToString("N"))

        New-Item `
            -ItemType Directory `
            -Path $stagingRoot `
            -Force `
            -ErrorAction Stop | Out-Null

        # Save staging path globally for later steps / cleanup
        $script:Config.CacheRoot = $stagingRoot
        $script:Config.StagingRoot = $stagingRoot

        Write-Log "Temporary staging directory created."
        Write-Log "Staging: $stagingRoot"

    }
    catch {

        Write-Log `
            "Cannot create temporary staging directory: $($_.Exception.Message)" `
            "ERROR"

        throw
    }

    # ========================================
    # Package destination
    # ========================================

    $destination = Join-Path `
        $stagingRoot `
        $safeFilename

    # ========================================
    # API URL
    # ========================================

    $uri = $script:Config.ApiBaseUrl +
        $script:Config.DownloadEndpoint

    Write-Log "Downloading package..."
    Write-Log "Filename: $safeFilename"

    # ========================================
    # Authorization
    # ========================================

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

        # ========================================
        # Validate downloaded file
        # ========================================

        if (-not (Test-Path -LiteralPath $destination)) {

            throw "Downloaded package does not exist."
        }

        $file = Get-Item `
            -LiteralPath $destination `
            -ErrorAction Stop

        if ($file.Length -le 0) {

            throw "Downloaded package is empty."
        }

        Write-Log `
            "Package downloaded: $($file.Length) bytes" `
            "OK"

        Write-Log `
            "Package path: $destination"

        return $destination
    }
    catch {

        Write-Log `
            "Package download failed: $($_.Exception.Message)" `
            "ERROR"

        # Remove package
        if (Test-Path -LiteralPath $destination) {

            Remove-Item `
                -LiteralPath $destination `
                -Force `
                -ErrorAction SilentlyContinue
        }

        # Remove staging directory
        if (
            $stagingRoot -and
            (Test-Path -LiteralPath $stagingRoot)
        ) {

            Remove-Item `
                -LiteralPath $stagingRoot `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }

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

function Test-PackageSignature {

    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$Signature,

        [Parameter(Mandatory = $true)]
        [string]$PublicKeyXml
    )

    Write-Log "Verifying package RSA signature..." -Level INFO

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Package file not found: $FilePath"
    }

    if ([string]::IsNullOrWhiteSpace($Signature)) {
        throw "Package signature is missing."
    }

    if ([string]::IsNullOrWhiteSpace($PublicKeyXml)) {
        throw "Package signing public key is missing."
    }

    $rsa = $null

    try {

        # ------------------------------------------------------
        # Decode Base64 signature
        # ------------------------------------------------------

        try {
            $signatureBytes = [Convert]::FromBase64String(
                $Signature.Trim()
            )

        }
        catch {

            throw "Package signature is not valid Base64."
        }


        # ------------------------------------------------------
        # Create RSA
        # ------------------------------------------------------

        $rsa = New-Object `
            System.Security.Cryptography.RSACryptoServiceProvider

        $rsa.FromXmlString($PublicKeyXml)


        # ------------------------------------------------------
        # Read package
        # ------------------------------------------------------

        $packageBytes = [System.IO.File]::ReadAllBytes($FilePath)


        # ------------------------------------------------------
        # Verify
        # ------------------------------------------------------

        $valid = $rsa.VerifyData(
            $packageBytes,
            "SHA256",
            $signatureBytes
        )


        if (-not $valid) {

            Write-Log `
                "Package RSA signature verification FAILED." `
                "ERROR"

            return $false
        }


        Write-Log `
            "Package RSA signature verification OK." `
            "OK"

        return $true

    }
    catch {

        Write-Log `
            "Package signature verification error: $($_.Exception.Message)" `
            "ERROR"

        return $false
    }
    finally {

        if ($null -ne $rsa) {
            $rsa.Dispose()
        }
    }
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
    
        if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {

            throw "Package entrypoint install.ps1 was not found."
        }

        Write-Log `
            "Package entrypoint found: install.ps1" `
            -Level OK

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

    Write-Log "Cleaning temporary files..."

    $stagingRoot = $script:Config.CacheRoot

    if ([string]::IsNullOrWhiteSpace($stagingRoot)) {

        Write-Log "No temporary staging directory to clean." "INFO"

        return
    }

    if (-not (Test-Path -LiteralPath $stagingRoot)) {

        Write-Log "Temporary staging directory already removed." "INFO"

        $script:Config.CacheRoot = $null

        return
    }

    try {

        Write-Log "Removing staging directory..."
        Write-Log "Path: $stagingRoot"

        Remove-Item `
            -LiteralPath $stagingRoot `
            -Recurse `
            -Force `
            -ErrorAction Stop

        Write-Log `
            "Temporary staging removed successfully." `
            "OK"
    }
    catch {

        Write-Log `
            "Cleanup warning: $($_.Exception.Message)" `
            "WARN"
    }
    finally {

        $script:Config.CacheRoot = $null
    }
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

    Write-Log `
        "Package signature verification enabled." `
        "INFO"

    if ([string]::IsNullOrWhiteSpace($package.signature)) {

        throw "Package signature is missing."
    }

    $signatureValid = Test-PackageSignature `
        -FilePath $packageFile `
        -Signature $package.signature `
        -PublicKeyXml $script:Config.SigningPublicKeyXml

    if (-not $signatureValid) {

        throw "Package signature verification failed."
    }

}
else {

    Write-Log `
        "Package signature verification is disabled." `
        "WARN"
}

    # --------------------------------------------------------------------------
    # 8. EXTRACT
    # --------------------------------------------------------------------------
    Write-Log "Preparing package staging..." -Level INFO

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

    Remove-TemporaryFiles

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