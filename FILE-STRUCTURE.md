# NetBird Self-Hosted Deployer - File Structure

This document describes the file structure and purpose of each file in the NetBird self-hosted deployment package.

## 📁 Package Contents

```
netbird-selfhosted-deployer/
├── deploy-netbird-selfhosted.sh          # Main deployment script (Linux/macOS)
├── run-deployment-windows.ps1            # Windows PowerShell deployment runner
├── run-deployment-windows.bat            # Windows batch deployment runner
├── docker-runner/                        # Docker container setup
│   └── Dockerfile                        # Container definition for Windows Docker method
├── README.md                             # Main documentation and quick start guide
├── WINDOWS-DEPLOYMENT.md                 # Comprehensive Windows deployment guide
├── FILE-STRUCTURE.md                     # This file - package structure documentation
└── docs/                                 # Additional documentation (if present)
    ├── TROUBLESHOOTING.md
    ├── ADVANCED-CONFIG.md
    └── SECURITY.md
```

## 📄 File Descriptions

### Core Deployment Files

#### `deploy-netbird-selfhosted.sh`
- **Purpose**: Main deployment script for Linux and macOS
- **Language**: Bash shell script
- **Features**:
  - Complete NetBird infrastructure deployment on Hetzner Cloud
  - Azure AD SPA integration with PKCE authentication
  - SSL certificate management with Let's Encrypt
  - Enhanced management script deployment
  - SSH alias creation and configuration
  - Nginx SPA routing fixes
- **Usage**: `./deploy-netbird-selfhosted.sh`

### Windows Support Files

#### `run-deployment-windows.ps1`
- **Purpose**: PowerShell script for Windows deployment
- **Language**: PowerShell 5.1+
- **Features**:
  - Auto-detection of available deployment methods (WSL, Git Bash, Docker)
  - Automatic prerequisite installation
  - Guided setup process with error handling
  - Support for multiple Windows execution environments
- **Usage**: `.\run-deployment-windows.ps1 [options]`
- **Options**:
  - `-UseWSL`: Force WSL method
  - `-UseGitBash`: Force Git Bash method
  - `-UseDocker`: Force Docker method
  - `-Help`: Show help information

#### `run-deployment-windows.bat`
- **Purpose**: Simple batch file for Docker-based deployment
- **Language**: Windows Batch
- **Features**:
  - Docker Desktop integration
  - Interactive container session
  - Simplified execution for non-PowerShell users
- **Usage**: Double-click or run `run-deployment-windows.bat`

### Docker Support

#### `docker-runner/Dockerfile`
- **Purpose**: Container definition for Windows Docker deployment
- **Base Image**: Ubuntu 22.04
- **Includes**:
  - Hetzner Cloud CLI
  - jq (JSON processor)
  - OpenSSH client
  - All required deployment tools
- **Usage**: Automatically built by Windows deployment scripts

### Documentation Files

#### `README.md`
- **Purpose**: Main project documentation
- **Contents**:
  - Feature overview and benefits
  - Quick start instructions for all platforms
  - Prerequisites and requirements
  - Setup process walkthrough
  - Configuration options
  - Server management instructions
  - Troubleshooting basics

#### `WINDOWS-DEPLOYMENT.md`
- **Purpose**: Comprehensive Windows deployment guide
- **Contents**:
  - Detailed setup instructions for each Windows method
  - Prerequisites and system requirements
  - Step-by-step installation guides
  - Windows-specific troubleshooting
  - FAQ for Windows users
  - Performance and compatibility notes

#### `FILE-STRUCTURE.md`
- **Purpose**: This file - explains package structure
- **Contents**:
  - File descriptions and purposes
  - Usage instructions for each file
  - Deployment workflow explanation
  - File relationships and dependencies

## 🔄 Deployment Workflow

### Linux/macOS Workflow
```
User runs deploy-netbird-selfhosted.sh
    ↓
Script checks prerequisites (hcloud, jq, ssh)
    ↓
Interactive setup (Hetzner API, Azure AD, domain)
    ↓
Server creation and configuration
    ↓
NetBird installation and setup
    ↓
Enhanced management script deployment
    ↓
SSL certificate provisioning
    ↓
Final verification and summary
```

### Windows Workflow
```
User runs run-deployment-windows.ps1
    ↓
Script detects available methods (WSL/Git Bash/Docker)
    ↓
Installs prerequisites if needed
    ↓
Launches appropriate environment
    ↓
Executes deploy-netbird-selfhosted.sh in chosen environment
    ↓
Same deployment process as Linux/macOS
```

### Docker Workflow
```
User runs run-deployment-windows.bat
    ↓
Docker builds container from Dockerfile
    ↓
Container mounts project directory
    ↓
Interactive shell session in container
    ↓
User runs deploy-netbird-selfhosted.sh manually
    ↓
Deployment proceeds in isolated Linux environment
```

## 🔧 File Relationships

### Dependencies
- **PowerShell script** → calls **main deployment script**
- **Batch file** → builds **Dockerfile** → runs **main deployment script**
- **Main script** → creates **enhanced management script** on server
- **All methods** → require **Hetzner Cloud CLI** and **jq**

### Configuration Flow
1. **User input** collected by platform-specific runners
2. **Environment setup** handled by Windows scripts
3. **Actual deployment** performed by main bash script
4. **Server management** enabled through deployed management script

## 📋 Usage Matrix

| Platform | Recommended File | Alternative Files |
|----------|------------------|-------------------|
| **Linux** | `deploy-netbird-selfhosted.sh` | N/A |
| **macOS** | `deploy-netbird-selfhosted.sh` | N/A |
| **Windows + WSL** | `run-deployment-windows.ps1 -UseWSL` | `deploy-netbird-selfhosted.sh` (in WSL) |
| **Windows + Git Bash** | `run-deployment-windows.ps1 -UseGitBash` | `deploy-netbird-selfhosted.sh` (in Git Bash) |
| **Windows + Docker** | `run-deployment-windows.ps1 -UseDocker` | `run-deployment-windows.bat` |

## 🛠️ Customization

### Adding New Features
- **Main functionality**: Modify `deploy-netbird-selfhosted.sh`
- **Windows support**: Update `run-deployment-windows.ps1`
- **Docker environment**: Modify `docker-runner/Dockerfile`

### Documentation Updates
- **General docs**: Update `README.md`
- **Windows-specific**: Update `WINDOWS-DEPLOYMENT.md`
- **File changes**: Update this `FILE-STRUCTURE.md`

## 🔒 Security Considerations

### File Permissions
- **Scripts**: Should be executable (`chmod +x *.sh`)
- **Configs**: Should be readable but not executable
- **SSH keys**: Will be created with proper permissions (600)

### Windows Security
- **PowerShell execution policy**: May need adjustment
- **Antivirus exceptions**: May be required for deployment tools
- **UAC elevation**: Required for some installations (WSL, Docker)

## 📊 File Sizes (Approximate)

| File | Size | Purpose |
|------|------|---------|
| `deploy-netbird-selfhosted.sh` | ~150KB | Main deployment logic |
| `run-deployment-windows.ps1` | ~25KB | Windows PowerShell runner |
| `run-deployment-windows.bat` | ~3KB | Simple Windows batch runner |
| `docker-runner/Dockerfile` | ~1KB | Container definition |
| `README.md` | ~30KB | Main documentation |
| `WINDOWS-DEPLOYMENT.md` | ~45KB | Windows-specific guide |
| `FILE-STRUCTURE.md` | ~8KB | This documentation |

**Total package size**: ~260KB (scripts and docs only)

## 🚀 Quick Reference

### For Linux/macOS Users
```bash
# Make executable and run
chmod +x deploy-netbird-selfhosted.sh
./deploy-netbird-selfhosted.sh
```

### For Windows Users
```powershell
# Auto-detect best method
.\run-deployment-windows.ps1

# Or specify method
.\run-deployment-windows.ps1 -UseWSL
```

### For Docker Users
```batch
# Simple execution
run-deployment-windows.bat
```

---

**Last updated**: January 2025  
**Package version**: 2.2.0  
**Maintained by**: [Panoptic IT Solutions](https://panoptic.ie)