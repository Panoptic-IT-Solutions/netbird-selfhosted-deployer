# NetBird Self-Hosted Deployment Tool

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.2.0-blue.svg)](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer)

A comprehensive deployment tool for setting up NetBird self-hosted infrastructure on Hetzner Cloud with Azure AD Single Page Application (SPA) authentication.

## 🚀 Features

- **Azure AD SPA Integration**: Modern OAuth2 PKCE-based authentication (no client secrets required)
- **Automated Infrastructure**: Complete Hetzner Cloud setup including servers, firewalls, and networking
- **SSL Certificate Management**: Automatic Let's Encrypt certificate provisioning
- **Nginx SPA Routing**: Fixed OAuth callback handling for Single Page Applications
- **Security Hardened**: SSH key authentication, firewall rules, and security updates
- **One-Click Deployment**: Fully automated setup process

## 📋 Prerequisites

Before running this deployment tool, ensure you have:

1. **Hetzner Cloud Account**
   - Active Hetzner Cloud account
   - API token with read/write permissions
   - Available server quota

2. **Azure AD Tenant**
   - Azure Active Directory tenant
   - Admin permissions to create app registrations
   - Domain for NetBird dashboard (e.g., `nb.yourdomain.com`)

3. **Domain Configuration**
   - Domain name pointing to your future server IP
   - DNS management access

## 🛠️ Quick Start

### Option 1: One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/main/install.sh | bash
```

### Option 2: Manual Installation

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

## 📚 Documentation

- [Azure AD SPA Setup Guide](./AZURE-AD-SPA-SETUP.md) - Complete Azure AD configuration
- [Troubleshooting Guide](./docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Advanced Configuration](./docs/ADVANCED-CONFIG.md) - Custom setups and modifications
- [Security Best Practices](./docs/SECURITY.md) - Hardening your deployment

## 🔍 What's Fixed in v2.2.0

This version addresses critical issues found in standard NetBird deployments:

### OAuth Authentication Issues ✅
- **400 Bad Request errors** during token exchange
- **PKCE vs Client Secret conflicts**
- **Token exchange failures**

### Nginx Configuration Issues ✅
- **404 errors** on `/auth` callback routes
- **SPA routing** problems with OAuth callbacks
- **Incorrect try_files directive**

### Key Technical Improvements
- Proper Azure AD SPA configuration (PKCE-only)
- Fixed nginx configuration for SPA routing
- Enhanced error handling and logging
- Comprehensive setup validation

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