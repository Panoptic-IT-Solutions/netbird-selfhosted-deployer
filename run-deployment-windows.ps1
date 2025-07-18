# NetBird Windows Deployment Runner (PowerShell)
# This script runs the NetBird deployment on Windows using WSL or Git Bash

param(
    [switch]$UseWSL,
    [switch]$UseGitBash,
    [switch]$UseDocker,
    [switch]$Help
)

# Colors for output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Purple = "`e[35m"
$Cyan = "`e[36m"
$Reset = "`e[0m"

function Write-Status {
    param($Message)
    Write-Host "${Blue}[INFO]${Reset} $Message"
}

function Write-Success {
    param($Message)
    Write-Host "${Green}[SUCCESS]${Reset} $Message"
}

function Write-Warning {
    param($Message)
    Write-Host "${Yellow}[WARNING]${Reset} $Message"
}

function Write-Error {
    param($Message)
    Write-Host "${Red}[ERROR]${Reset} $Message"
}

function Write-Header {
    param($Message)
    Write-Host "${Purple}$Message${Reset}"
}

function Show-Banner {
    @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        🚀 NetBird Windows Deployment Runner                  ║
║                                                               ║
║        PowerShell Edition - Multiple Execution Methods       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"@ | Write-Host -ForegroundColor Cyan
}

function Show-Help {
    @"

NetBird Windows Deployment Runner

USAGE:
    .\run-deployment-windows.ps1 [OPTIONS]

OPTIONS:
    -UseWSL         Use Windows Subsystem for Linux (Recommended)
    -UseGitBash     Use Git Bash (Requires Git for Windows)
    -UseDocker      Use Docker container method
    -Help           Show this help message

EXAMPLES:
    .\run-deployment-windows.ps1 -UseWSL
    .\run-deployment-windows.ps1 -UseGitBash
    .\run-deployment-windows.ps1 -UseDocker

PREREQUISITES:
    WSL Method:      Windows 10/11 with WSL installed
    Git Bash:        Git for Windows installed
    Docker Method:   Docker Desktop installed

"@ | Write-Host
}

function Test-WSL {
    try {
        $wslVersion = wsl --version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

function Test-GitBash {
    $gitBashPath = @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "${env:LOCALAPPDATA}\Programs\Git\bin\bash.exe"
    )

    foreach ($path in $gitBashPath) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Test-Docker {
    try {
        docker --version 2>$null | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Install-WSLPrerequisites {
    Write-Status "Installing prerequisites in WSL..."

    $commands = @(
        "sudo apt-get update",
        "sudo apt-get install -y curl jq openssh-client",
        "curl -s https://packages.hetzner.com/hcloud/deb/hcloud-source.list | sudo tee /etc/apt/sources.list.d/hcloud.list",
        "curl -s https://packages.hetzner.com/hcloud/deb/conf/hetzner.gpg | sudo apt-key add -",
        "sudo apt-get update",
        "sudo apt-get install -y hcloud-cli"
    )

    foreach ($cmd in $commands) {
        Write-Status "Running: $cmd"
        wsl -- bash -c $cmd
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Command failed, but continuing..."
        }
    }

    Write-Success "WSL prerequisites installation completed"
}

function Run-WithWSL {
    Write-Header "=== Running with WSL ==="

    if (-not (Test-WSL)) {
        Write-Error "WSL is not installed or not available"
        Write-Status "Install WSL with: wsl --install"
        Write-Status "Then restart your computer and run this script again"
        return
    }

    Write-Success "WSL detected"

    # Check if prerequisites are installed
    Write-Status "Checking WSL prerequisites..."

    $hcloudInstalled = wsl -- bash -c "command -v hcloud >/dev/null 2>&1; echo `$?"
    if ($hcloudInstalled -ne "0") {
        Write-Warning "Hetzner Cloud CLI not found in WSL"
        $install = Read-Host "Install prerequisites? (y/N)"
        if ($install -eq "y" -or $install -eq "Y") {
            Install-WSLPrerequisites
        } else {
            Write-Error "Prerequisites required. Exiting."
            return
        }
    }

    # Convert Windows path to WSL path
    $currentPath = Get-Location
    $wslPath = $currentPath.Path -replace "^([A-Z]):", "/mnt/$($matches[1].ToLower())" -replace "\\", "/"

    Write-Status "Running NetBird deployment script in WSL..."
    Write-Status "WSL Path: $wslPath"

    # Run the deployment script
    wsl -- bash -c "cd '$wslPath' && ./deploy-netbird-selfhosted.sh"
}

function Run-WithGitBash {
    Write-Header "=== Running with Git Bash ==="

    $bashPath = Test-GitBash
    if (-not $bashPath) {
        Write-Error "Git Bash not found"
        Write-Status "Install Git for Windows from: https://git-scm.com/download/win"
        return
    }

    Write-Success "Git Bash found at: $bashPath"

    # Check for prerequisites
    Write-Status "Checking Git Bash prerequisites..."

    $scriptDir = Get-Location
    $deployScript = Join-Path $scriptDir "deploy-netbird-selfhosted.sh"

    if (-not (Test-Path $deployScript)) {
        Write-Error "Deployment script not found at: $deployScript"
        return
    }

    Write-Status "Running NetBird deployment script with Git Bash..."

    # Run the deployment script
    & $bashPath -c "cd '$($scriptDir.Path -replace '\\', '/')' && ./deploy-netbird-selfhosted.sh"
}

function Run-WithDocker {
    Write-Header "=== Running with Docker ==="

    if (-not (Test-Docker)) {
        Write-Error "Docker is not installed or not running"
        Write-Status "Install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
        return
    }

    Write-Success "Docker detected"

    # Check if Dockerfile exists
    $dockerFile = Join-Path (Get-Location) "docker-runner\Dockerfile"
    if (-not (Test-Path $dockerFile)) {
        Write-Error "Dockerfile not found at: $dockerFile"
        Write-Status "Make sure you have the docker-runner directory with Dockerfile"
        return
    }

    Write-Status "Building Docker image..."
    docker build -t netbird-deployer docker-runner/

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build Docker image"
        return
    }

    Write-Success "Docker image built successfully"
    Write-Status "Starting interactive deployment session..."
    Write-Warning "In the container, run: ./deploy-netbird-selfhosted.sh"

    # Run the container
    docker run -it --rm `
        -v "${PWD}:/netbird" `
        -v "${env:USERPROFILE}\.ssh:/root/.ssh:ro" `
        -v "${env:USERPROFILE}\.config\hcloud:/root/.config/hcloud" `
        netbird-deployer
}

function Auto-Detect {
    Write-Header "=== Auto-detecting best method ==="

    if (Test-WSL) {
        Write-Success "WSL detected - using WSL method (recommended)"
        Run-WithWSL
    } elseif (Test-GitBash) {
        Write-Success "Git Bash detected - using Git Bash method"
        Run-WithGitBash
    } elseif (Test-Docker) {
        Write-Success "Docker detected - using Docker method"
        Run-WithDocker
    } else {
        Write-Error "No compatible environment found!"
        Write-Status "Please install one of the following:"
        Write-Status "  - WSL: wsl --install"
        Write-Status "  - Git for Windows: https://git-scm.com/download/win"
        Write-Status "  - Docker Desktop: https://www.docker.com/products/docker-desktop/"
    }
}

# Main execution
Show-Banner

if ($Help) {
    Show-Help
    exit 0
}

# Check if script is in the right location
$deployScript = Join-Path (Get-Location) "deploy-netbird-selfhosted.sh"
if (-not (Test-Path $deployScript)) {
    Write-Error "NetBird deployment script not found!"
    Write-Status "Make sure you're running this script from the netbird-selfhosted-deployer directory"
    Write-Status "Expected location: $deployScript"
    exit 1
}

# Execute based on parameters
if ($UseWSL) {
    Run-WithWSL
} elseif ($UseGitBash) {
    Run-WithGitBash
} elseif ($UseDocker) {
    Run-WithDocker
} else {
    Auto-Detect
}

Write-Status "Deployment runner finished"
