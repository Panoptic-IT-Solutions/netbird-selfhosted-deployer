# NetBird Agent Installation Script for Windows (Datto RMM)
# Optional: Provide SetupKey to bypass SSO, otherwise requires Azure AD authentication
param(
    [Parameter(Mandatory=$true)]
    [string]$ManagementURL,

    [Parameter(Mandatory=$false)]
    [string]$SetupKey = ""
)

$ErrorActionPreference = "Stop"

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator. Please run PowerShell as Administrator and try again."
    exit 1
}

Write-Host "====================================="
Write-Host "NetBird Agent Installation"
Write-Host "====================================="
Write-Host "Management URL: $ManagementURL"

if ($SetupKey) {
    Write-Host "Setup Key: Provided (will bypass SSO)"
} else {
    Write-Host "Setup Key: Not provided (will require Azure AD SSO)"
}

# Download NetBird installer
$installerUrl = "https://pkgs.netbird.io/windows/x64"
$installerPath = "$env:TEMP\netbird-installer.exe"

Write-Host ""
Write-Host "Step 1: Downloading NetBird installer..."
Write-Host "URL: $installerUrl"

try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "Download completed: $installerPath"
} catch {
    Write-Error "Failed to download NetBird installer: $_"
    exit 1
}

# Verify download
if (-not (Test-Path $installerPath)) {
    Write-Error "Installer file not found after download"
    exit 1
}

Write-Host ""
Write-Host "Step 2: Installing NetBird..."
Write-Host "This may take 30-60 seconds..."

try {
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -PassThru -Wait
    Write-Host "Installer exit code: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        Write-Warning "Installer returned non-zero exit code: $($process.ExitCode)"
    }
} catch {
    Write-Error "Failed to run installer: $_"
    exit 1
}

# Wait for service to be available
Write-Host ""
Write-Host "Step 3: Waiting for NetBird service to initialize..."
Start-Sleep -Seconds 5

# Path to NetBird executable
$netbirdExe = "C:\Program Files\NetBird\netbird.exe"

if (-not (Test-Path $netbirdExe)) {
    Write-Error "NetBird executable not found at $netbirdExe"
    exit 1
}

if ($SetupKey) {
    # Connect with setup key (bypass SSO)
    Write-Host ""
    Write-Host "Step 4: Connecting to NetBird with setup key..."

    # Check if default WireGuard port 51820 is in use
    $port51820InUse = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object LocalPort -eq 51820

    try {
        if ($port51820InUse) {
            Write-Warning "Port 51820 is in use, using alternative port 51821"
            & $netbirdExe up --setup-key $SetupKey --management-url $ManagementURL --wireguard-port 51821
        } else {
            & $netbirdExe up --setup-key $SetupKey --management-url $ManagementURL
        }
        Write-Host "Connection command executed"
    } catch {
        Write-Error "Failed to connect to NetBird: $_"
        exit 1
    }

    # Verify connection
    Write-Host "Verifying connection..."
    Start-Sleep -Seconds 3

    $service = Get-Service -Name "netbird" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host ""
        Write-Host "========================================="
        Write-Host "SUCCESS: NetBird Connected!"
        Write-Host "========================================="
        & $netbirdExe status
    } else {
        Write-Warning "NetBird service status could not be verified"
        Write-Host "You may need to manually start NetBird from the system tray"
    }
} else {
    # Configure management URL only (requires SSO)
    Write-Host ""
    Write-Host "Step 4: Configuring NetBird management URL..."
    $configPath = "$env:ProgramData\NetBird\config.json"

    # Create config directory if it doesn't exist
    $configDir = Split-Path -Parent $configPath
    if (-not (Test-Path $configDir)) {
        try {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Write-Host "Created config directory: $configDir"
        } catch {
            Write-Error "Failed to create config directory: $_"
            exit 1
        }
    }

    # Create basic config with management URL
    $config = @{
        ManagementURL = $ManagementURL
    } | ConvertTo-Json

    try {
        Set-Content -Path $configPath -Value $config -Force
        Write-Host "Configuration saved to: $configPath"
    } catch {
        Write-Error "Failed to write configuration file: $_"
        exit 1
    }

    Write-Host ""
    Write-Host "========================================="
    Write-Host "NetBird Agent Installed Successfully!"
    Write-Host "========================================="
    Write-Host ""
    Write-Host "IMPORTANT: User Action Required"
    Write-Host ""
    Write-Host "The user must authenticate via Azure AD to connect:"
    Write-Host ""
    Write-Host "  1. Look for NetBird icon in system tray"
    Write-Host "  2. Click the icon and select 'Connect'"
    Write-Host "  3. Browser will open for Azure AD login"
    Write-Host "  4. Sign in with company credentials"
    Write-Host ""
}

Write-Host ""
Write-Host "NetBird deployment complete!"
