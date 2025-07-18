# NetBird Windows Deployment Guide

[![Windows](https://img.shields.io/badge/Windows-10%2F11-blue.svg)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/)
[![WSL](https://img.shields.io/badge/WSL-2-green.svg)](https://docs.microsoft.com/windows/wsl/)

This guide provides comprehensive instructions for deploying NetBird self-hosted infrastructure from Windows machines using various methods.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: WSL (Recommended)](#method-1-wsl-recommended)
- [Method 2: Git Bash](#method-2-git-bash)
- [Method 3: Docker Container](#method-3-docker-container)
- [Method 4: PowerShell Helper Script](#method-4-powershell-helper-script)
- [Troubleshooting](#troubleshooting)
- [Common Issues](#common-issues)
- [FAQ](#faq)

## Prerequisites

### System Requirements

- **Windows 10** (version 1903 or later) or **Windows 11**
- **PowerShell 5.1** or later (included with Windows)
- **Administrator privileges** for some installations
- **Internet connection** for downloading tools and packages

### Required Accounts

- **Hetzner Cloud Account** with API token
- **Azure AD Tenant** with admin permissions
- **Domain name** for NetBird dashboard

## Method 1: WSL (Recommended)

Windows Subsystem for Linux provides the most seamless experience for running bash scripts on Windows.

### 🚀 Quick Start with WSL

1. **Install WSL (if not already installed):**
   ```powershell
   # Open PowerShell as Administrator
   wsl --install
   ```

2. **Restart your computer** when prompted

3. **Run the deployment:**
   ```powershell
   .\run-deployment-windows.ps1 -UseWSL
   ```

### 📋 Detailed WSL Setup

#### Step 1: Enable WSL

Open PowerShell as Administrator and run:

```powershell
# Enable WSL feature
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Enable Virtual Machine Platform
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Install WSL 2 (recommended)
wsl --install
```

#### Step 2: Install Linux Distribution

If WSL was already enabled, install Ubuntu:

```powershell
# Install Ubuntu (default)
wsl --install -d Ubuntu

# Or choose from available distributions
wsl --list --online
wsl --install -d Ubuntu-22.04
```

#### Step 3: Set Up Prerequisites

The PowerShell script will automatically install these, but you can also do it manually:

```bash
# Inside WSL
sudo apt-get update
sudo apt-get install -y curl jq openssh-client

# Install Hetzner Cloud CLI
curl -s https://packages.hetzner.com/hcloud/deb/hcloud-source.list | sudo tee /etc/apt/sources.list.d/hcloud.list
curl -s https://packages.hetzner.com/hcloud/deb/conf/hetzner.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y hcloud-cli
```

#### Step 4: Run Deployment

```powershell
# From Windows PowerShell in the project directory
.\run-deployment-windows.ps1 -UseWSL
```

### 🔧 WSL Benefits

- ✅ **Native bash support** - Scripts run exactly as on Linux
- ✅ **Best compatibility** - All features work perfectly
- ✅ **Easy package management** - Standard Linux package managers
- ✅ **SSH integration** - Native SSH client support
- ✅ **File system integration** - Access Windows files from WSL

## Method 2: Git Bash

Git Bash provides a minimal bash environment that's sufficient for most deployment tasks.

### 🚀 Quick Start with Git Bash

1. **Install Git for Windows** from [git-scm.com](https://git-scm.com/download/win)

2. **Run the deployment:**
   ```powershell
   .\run-deployment-windows.ps1 -UseGitBash
   ```

### 📋 Detailed Git Bash Setup

#### Step 1: Install Git for Windows

1. Download from [https://git-scm.com/download/win](https://git-scm.com/download/win)
2. Run the installer with default settings
3. Ensure "Git Bash Here" is selected during installation

#### Step 2: Install Prerequisites

Download and install these tools:

**Hetzner Cloud CLI:**
```bash
# Download to your project directory
curl -L https://github.com/hetznercloud/cli/releases/latest/download/hcloud-windows-amd64.exe -o hcloud.exe
```

**jq (JSON processor):**
```bash
# Download to your project directory
curl -L https://github.com/stedolan/jq/releases/latest/download/jq-win64.exe -o jq.exe
```

#### Step 3: Add Tools to PATH

Either:
- Place `hcloud.exe` and `jq.exe` in the same directory as your deployment script
- Or add their location to your Windows PATH environment variable

#### Step 4: Run Deployment

Right-click in your project folder and select "Git Bash Here", then:

```bash
./netbird-selfhosted-deployer/deploy-netbird-selfhosted.sh
```

Or use the PowerShell helper:

```powershell
.\run-deployment-windows.ps1 -UseGitBash
```

### 🔧 Git Bash Benefits

- ✅ **Lightweight installation** - Minimal overhead
- ✅ **No virtualization** - Runs directly on Windows
- ✅ **Familiar interface** - Standard bash environment
- ✅ **Good compatibility** - Most bash scripts work

### ⚠️ Git Bash Limitations

- ❌ **Limited package management** - Manual tool installation
- ❌ **Some compatibility issues** - Complex scripts may fail
- ❌ **No systemd** - Some Linux-specific features unavailable

## Method 3: Docker Container

Run the deployment in a containerized Linux environment.

### 🚀 Quick Start with Docker

1. **Install Docker Desktop** from [docker.com](https://www.docker.com/products/docker-desktop/)

2. **Run the deployment:**
   ```batch
   run-deployment-windows.bat
   ```

### 📋 Detailed Docker Setup

#### Step 1: Install Docker Desktop

1. Download from [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/)
2. Run the installer
3. Restart your computer when prompted
4. Start Docker Desktop and complete setup

#### Step 2: Verify Docker Installation

```powershell
# Check Docker is running
docker --version
docker run hello-world
```

#### Step 3: Run Deployment Container

**Option A: Using Batch File**
```batch
run-deployment-windows.bat
```

**Option B: Using PowerShell**
```powershell
.\run-deployment-windows.ps1 -UseDocker
```

**Option C: Manual Docker Commands**
```powershell
# Build the container
docker build -t netbird-deployer docker-runner/

# Run interactively
docker run -it --rm `
    -v "${PWD}:/netbird" `
    -v "${env:USERPROFILE}\.ssh:/root/.ssh:ro" `
    -v "${env:USERPROFILE}\.config\hcloud:/root/.config/hcloud" `
    netbird-deployer

# Inside the container, run:
./netbird-selfhosted-deployer/deploy-netbird-selfhosted.sh
```

### 🔧 Docker Benefits

- ✅ **Complete isolation** - Clean Linux environment
- ✅ **Consistent behavior** - Same as Linux deployment
- ✅ **All tools included** - No manual installation needed
- ✅ **Reproducible** - Same environment every time

### ⚠️ Docker Limitations

- ❌ **Larger download** - Docker Desktop is ~500MB
- ❌ **Resource usage** - Requires more RAM and CPU
- ❌ **Complex setup** - More moving parts

## Method 4: PowerShell Helper Script

Our PowerShell script automates the deployment process regardless of which method you choose.

### 🚀 Script Features

- **Auto-detection** of available tools (WSL, Git Bash, Docker)
- **Automatic prerequisite installation** where possible
- **Guided setup process** with clear instructions
- **Error handling and troubleshooting** assistance

### 📋 Script Usage

#### Basic Usage

```powershell
# Auto-detect best method
.\run-deployment-windows.ps1

# Force specific method
.\run-deployment-windows.ps1 -UseWSL
.\run-deployment-windows.ps1 -UseGitBash
.\run-deployment-windows.ps1 -UseDocker

# Get help
.\run-deployment-windows.ps1 -Help
```

#### Script Options

| Parameter | Description |
|-----------|-------------|
| `-UseWSL` | Force use of Windows Subsystem for Linux |
| `-UseGitBash` | Force use of Git Bash environment |
| `-UseDocker` | Force use of Docker container method |
| `-Help` | Show detailed help information |

#### What the Script Does

1. **Checks prerequisites** for each method
2. **Installs missing tools** where possible
3. **Guides you through setup** with clear instructions
4. **Runs the deployment** using the chosen method
5. **Provides troubleshooting** if issues occur

## Troubleshooting

### Common Windows-Specific Issues

#### WSL Issues

**Problem**: WSL installation fails
```powershell
# Solution: Enable required Windows features
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
# Restart computer
```

**Problem**: WSL commands not found
```bash
# Solution: Update package lists and install tools
sudo apt-get update
sudo apt-get install -y curl jq openssh-client
```

**Problem**: Permission denied accessing Windows files
```bash
# Solution: Use proper WSL path
cd /mnt/c/Users/YourUsername/path/to/netbird
```

#### Git Bash Issues

**Problem**: `hcloud` command not found
```bash
# Solution: Download and place in project directory
curl -L https://github.com/hetznercloud/cli/releases/latest/download/hcloud-windows-amd64.exe -o hcloud.exe
chmod +x hcloud.exe
```

**Problem**: Script syntax errors
```bash
# Solution: Ensure proper line endings
dos2unix deploy-netbird-selfhosted.sh
```

#### Docker Issues

**Problem**: Docker not starting
```powershell
# Solution: Restart Docker Desktop service
Restart-Service com.docker.service
```

**Problem**: Container build fails
```powershell
# Solution: Check Docker Desktop is running and try again
docker system prune -f
docker build -t netbird-deployer docker-runner/
```

### Network and Authentication Issues

#### Hetzner Cloud API

**Problem**: Authentication failed
```bash
# Solution: Configure Hetzner Cloud CLI
hcloud context create myproject
# Enter your API token when prompted
```

**Problem**: Network timeout
```bash
# Solution: Check Windows Firewall and antivirus
# Add exceptions for hcloud.exe and ssh.exe
```

#### SSH Connection Issues

**Problem**: SSH key not found
```bash
# Solution: Generate SSH key if not exists
ssh-keygen -t ed25519 -C "your-email@example.com"
```

**Problem**: Permission denied (Windows file permissions)
```powershell
# Solution: Fix SSH key permissions
icacls $env:USERPROFILE\.ssh\id_ed25519 /inheritance:r /grant:r $env:USERNAME:F
```

## Common Issues

### PowerShell Execution Policy

If you get execution policy errors:

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow scripts for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or bypass for this session only
powershell -ExecutionPolicy Bypass -File .\run-deployment-windows.ps1
```

### Windows Defender and Antivirus

Some antivirus software may block the deployment tools:

1. **Add exceptions** for:
   - `hcloud.exe`
   - `ssh.exe`
   - Your project directory
   - Docker Desktop (if using Docker method)

2. **Temporarily disable** real-time protection during deployment

### Path and Environment Variables

Ensure tools are in your PATH:

```powershell
# Check if tools are available
where hcloud
where jq
where docker

# Add to PATH if needed (temporary)
$env:PATH += ";C:\path\to\your\tools"

# Or add permanently via System Properties > Environment Variables
```

### File Line Endings

Windows uses different line endings than Linux:

```bash
# Convert if needed (in Git Bash)
dos2unix *.sh
```

Or configure Git to handle this automatically:

```bash
git config --global core.autocrlf input
```

## FAQ

### Q: Which method should I choose?

**A:** We recommend WSL for the best experience. Here's the priority:

1. **WSL** - Most compatible, all features work
2. **Git Bash** - Good for simple deployments, lightweight
3. **Docker** - Best isolation, requires more resources

### Q: Can I switch between methods?

**A:** Yes! You can try different methods if one doesn't work for your environment.

### Q: Do I need administrator privileges?

**A:** 
- **WSL installation**: Yes, requires admin
- **WSL usage**: No, once installed
- **Git Bash**: Depends on installation location
- **Docker**: Yes, requires admin for installation

### Q: Will this work on Windows Server?

**A:** Yes, but you may need to:
- Enable WSL feature manually
- Install Docker Desktop manually
- Configure Windows Firewall exceptions

### Q: Can I use this in a corporate environment?

**A:** Usually yes, but check with your IT department about:
- WSL installation policies
- Docker Desktop licensing
- Network proxy configurations
- Firewall exceptions needed

### Q: What if my antivirus blocks the tools?

**A:** Add exceptions for:
- The entire NetBird project directory
- `hcloud.exe`, `ssh.exe`, `docker.exe`
- PowerShell script execution

### Q: How do I update the tools?

**A:** 
- **WSL**: `sudo apt-get update && sudo apt-get upgrade`
- **Git Bash**: Download latest versions manually
- **Docker**: Tools are updated when container is rebuilt

## Support

If you encounter issues not covered in this guide:

1. **Check the main [README.md](./README.md)** for general troubleshooting
2. **Review [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)** for detailed solutions
3. **Open an issue** on [GitHub Issues](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/issues)
4. **Join discussions** on [GitHub Discussions](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/discussions)

### Collecting Debug Information

When reporting issues, include:

```powershell
# System information
$PSVersionTable
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion

# WSL information (if using WSL)
wsl --list --verbose
wsl --version

# Docker information (if using Docker)
docker --version
docker system info

# Error messages and logs
```

---

**Made with ❤️ for Windows users by [Panoptic IT Solutions](https://panoptic.ie)**