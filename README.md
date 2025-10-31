# NetBird Self-Hosted Deployment Tool

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.3.0-blue.svg)](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer)

A comprehensive deployment tool for setting up NetBird self-hosted infrastructure on Hetzner Cloud with Azure AD Single Page Application (SPA) authentication and automatic token refresh management.

## 🚀 Features

- **Azure AD SPA Integration**: Modern OAuth2 PKCE-based authentication (no client secrets required)
- **Token Refresh Management**: Automatic IDP signing key refresh to prevent 401 authentication errors
- **Automated Infrastructure**: Complete Hetzner Cloud setup including servers, firewalls, and networking
- **SSL Certificate Management**: Automatic Let's Encrypt certificate provisioning
- **Nginx SPA Routing**: Fixed OAuth callback handling for Single Page Applications
- **Enhanced Management Script**: Comprehensive server management with SSL and Azure AD monitoring
- **SSH Alias Management**: Automatic company-named SSH aliases for easy server access
- **Security Hardened**: SSH key authentication, firewall rules, and security updates
- **One-Click Deployment**: Fully automated setup process

## 📋 Prerequisites

Before running this deployment tool, ensure you have:

1. **Operating System**
   - **Linux/macOS**: Native bash support
   - **Windows**: WSL, Git Bash, or Docker Desktop

2. **Hetzner Cloud Account**
   - Active Hetzner Cloud account
   - API token with read/write permissions
   - Available server quota

3. **Azure AD Tenant**
   - Azure Active Directory tenant
   - Admin permissions to create app registrations
   - Domain for NetBird dashboard (e.g., `nb.yourdomain.com`)

4. **Domain Configuration**
   - Domain name pointing to your future server IP
   - DNS management access

## 🛠️ Quick Start

### Linux/macOS Deployment

#### Option 1: One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/main/install.sh | bash
```

#### Option 2: Manual Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer.git
   cd netbird-selfhosted-deployer
   ```

2. **Make the script executable:**
   ```bash
   chmod +x deploy-netbird-selfhosted.sh
   ```

3. **Run the deployment:**
   ```bash
   ./deploy-netbird-selfhosted.sh
   ```

### Windows Deployment

We provide multiple options for running NetBird deployment on Windows:

#### Option 1: WSL (Recommended)

1. **Install WSL if not already installed:**
   ```powershell
   wsl --install
   ```

2. **Use the PowerShell helper script:**
   ```powershell
   .\run-deployment-windows.ps1 -UseWSL
   ```

#### Option 2: Git Bash

1. **Install Git for Windows** from [git-scm.com](https://git-scm.com/download/win)

2. **Run with Git Bash:**
   ```powershell
   .\run-deployment-windows.ps1 -UseGitBash
   ```

#### Option 3: Docker Container

1. **Install Docker Desktop** from [docker.com](https://www.docker.com/products/docker-desktop/)

2. **Run using Docker:**
   ```batch
   run-deployment-windows.bat
   ```
   Or with PowerShell:
   ```powershell
   .\run-deployment-windows.ps1 -UseDocker
   ```

#### Option 4: Auto-Detect (Easiest)

Let the script automatically choose the best available method:
```powershell
.\run-deployment-windows.ps1
```

The PowerShell script will:
- Detect what's available on your system (WSL, Git Bash, Docker)
- Install prerequisites automatically where possible
- Guide you through the setup process
- Handle the NetBird deployment seamlessly

## 📖 Setup Process

The deployment script will guide you through:

1. **Hetzner Cloud Setup**
   - API token configuration
   - SSH key selection/upload
   - Server creation and configuration

2. **Azure AD Configuration**
   - Step-by-step SPA app registration
   - Proper redirect URI setup
   - PKCE configuration guidance

3. **NetBird Installation**
   - Docker and Docker Compose setup
   - NetBird services deployment
   - SSL certificate provisioning

4. **Final Configuration**
   - Dashboard access verification
   - User management setup
   - Network configuration

## 🔧 Configuration Options

The script supports various configuration options:

- **Server Type**: Default `cax11` (ARM, 2 vCPU, 4GB RAM)
- **Location**: Default `nbg1` (Nuremberg, Germany)
- **Image**: Default `ubuntu-24.04`
- **Custom Domain**: Your NetBird dashboard domain
- **IP Assignment**: Automatic or use existing Primary IPs

## 🖥️ Server Management

### SSH Aliases
The deployment script automatically creates company-named SSH aliases for easy server access:

```bash
# Connect using short alias (e.g., for "NB2")
ssh nb2

# Run management commands using alias
ssh nb2 '/root/netbird-management.sh status'
ssh nb2 '/root/netbird-management.sh health'
```

### IP Address Management
Control IP assignment for consistent DNS and network configuration:

```bash
# List available Primary IPs
./deploy-netbird-selfhosted.sh list-ips

# Use specific Primary IP for deployment
./deploy-netbird-selfhosted.sh --customer "Acme Corp" --ip my-static-ip

# Create a new Primary IP first
hcloud primary-ip create --type ipv4 --location nbg1 --name my-ip --assignee-type server
```

**Primary IP Benefits:**
- IP persists if server is recreated
- Stable DNS records (no IP changes)
- Can be transferred between servers
- Same cost as regular IP (€0.50/month)

### List Saved Servers
View all deployed NetBird servers:

```bash
./deploy-netbird-selfhosted.sh list-servers
```

### Enhanced Management Script
Each server includes a comprehensive management script with these features:

- **Health Monitoring**: Complete system health checks
- **SSL Certificate Management**: Certificate status and renewal monitoring
- **Azure AD Integration Checks**: Authentication error detection and fixes
- **Service Management**: Start, stop, restart, and update services
- **Backup Management**: Configuration backup and restore
- **Connectivity Testing**: Domain and network connectivity verification

```bash
# Available management commands (using short alias or IP)
ssh nb2 '/root/netbird-management.sh health'     # Complete health check
ssh nb2 '/root/netbird-management.sh ssl'       # Check SSL certificates
ssh nb2 '/root/netbird-management.sh azure-fix' # Azure AD troubleshooting
ssh nb2 '/root/netbird-management.sh backup'    # Backup configuration
ssh nb2 '/root/netbird-management.sh test'      # Test connectivity
```

## 📚 Documentation

- [Windows Deployment Guide](./WINDOWS-DEPLOYMENT.md) - Detailed Windows setup instructions
- [Azure AD SPA Setup Guide](./AZURE-AD-SPA-SETUP.md) - Complete Azure AD configuration
- [Troubleshooting Guide](./docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Advanced Configuration](./docs/ADVANCED-CONFIG.md) - Custom setups and modifications
- [Security Best Practices](./docs/SECURITY.md) - Hardening your deployment

## 🔍 What's New in v2.3.0

### Token Refresh & Session Management ✅
- **Automatic IDP Signing Key Refresh**: Prevents 401 token validation errors when Azure AD rotates keys
- **Enhanced Token Handling**: Better long-running session support with `offline_access` scope
- **Improved Error Handling**: More robust directory structure verification during deployment
- **Configuration Verification**: Post-installation checks ensure all required files are present

### Previous Fixes (v2.2.0)

This version builds on critical fixes from v2.2.0:

#### OAuth Authentication Issues ✅
- **400 Bad Request errors** during token exchange
- **PKCE vs Client Secret conflicts**
- **Token exchange failures**

#### Nginx Configuration Issues ✅
- **404 errors** on `/auth` callback routes
- **SPA routing** problems with OAuth callbacks
- **Incorrect try_files directive**

#### Management Features ✅
- **Enhanced Management Script**: Comprehensive server monitoring and management
- **SSH Alias System**: Short, practical aliases for easy server access (e.g., `ssh nb2`)
- **Custom IP Assignment**: Use existing Primary IPs for stable network configuration
- **SSL Certificate Monitoring**: Automatic certificate status checks and renewal warnings
- **Azure AD Integration Monitoring**: Real-time authentication error detection
- **Backup Management**: Automated configuration backup and restore capabilities

### Key Technical Improvements
- **IDP signing key refresh enabled** in management.json to handle Azure AD key rotation
- Proper Azure AD SPA configuration (PKCE-only)
- Fixed nginx configuration for SPA routing
- Enhanced error handling and logging with debugging output
- Comprehensive setup validation with directory existence checks
- Automatic SSH known hosts and alias management with short, practical aliases
- Custom IP assignment using Hetzner Primary IPs
- Integrated server management tools

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Azure AD      │    │   Hetzner VM    │    │    NetBird      │
│   (SPA Auth)    │◄──►│   (Ubuntu)      │◄──►│   Dashboard     │
│                 │    │                 │    │                 │
│ - PKCE Flow     │    │ - Nginx         │    │ - Management    │
│ - No Secrets    │    │ - SSL Certs     │    │ - Signal        │
│ - Redirect URI  │    │ - Docker        │    │ - Relay         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🔒 Security Features

- **Modern OAuth2 PKCE**: No client secrets stored or transmitted
- **SSH Key Authentication**: Password authentication disabled
- **Firewall Rules**: Only necessary ports exposed
- **SSL/TLS Encryption**: Automatic Let's Encrypt certificates
- **Security Updates**: Automatic system updates enabled
- **SSH Key Management**: Automatic known hosts and short alias management
- **IP Management**: Support for custom Primary IP assignment

## 🐛 Troubleshooting

### Common Issues

1. **OAuth 400 Errors**
   - Ensure Azure AD app is configured as SPA
   - Verify redirect URI matches exactly
   - Check PKCE configuration

2. **404 on Auth Callbacks**
   - Nginx SPA routing fix included
   - Verify domain DNS resolution

3. **SSL Certificate Issues**
   - Ensure domain points to server IP
   - Check Let's Encrypt rate limits

For detailed troubleshooting, see [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md).

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

## 🙏 Acknowledgments

- [NetBird Team](https://github.com/netbirdio/netbird) for the amazing VPN solution
- [Hetzner Cloud](https://www.hetzner.com/cloud) for reliable infrastructure
- Community contributors and testers

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/discussions)
- **Email**: support@panoptic.ie

---

**Made with ❤️ by [Panoptic IT Solutions](https://panoptic.ie)**