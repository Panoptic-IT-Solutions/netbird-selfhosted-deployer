# Changelog

All notable changes to the NetBird Self-Hosted Deployer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2025-07-18

### Added
- ✨ **Universal Azure AD client support** with PKCE authentication for all NetBird client types
- 📱 **Multi-platform configuration** for web dashboard, desktop apps, mobile apps, and CLI tools
- 🌐 **Enhanced IP assignment logic** with support for Primary IP names and addresses
- 🔧 **Interactive IP selection** during deployment configuration
- 📋 **Enhanced management script** with health checks, SSL verification, and Azure AD troubleshooting
- 🛠️ **Improved Docker Compose detection** supporting both standalone and plugin versions
- 🔧 **Fixed SSH verification** eliminating false positive connection errors
- 🔧 **One-click installer script** for easy deployment
- 📚 **Comprehensive documentation suite** including troubleshooting and security guides
- 🛡️ **Enhanced security configurations** with fail2ban and UFW firewall
- 📊 **Advanced monitoring and logging** capabilities
- 🌐 **Multi-region deployment support** for global organizations
- 🔒 **Security hardening features** including automatic updates and SSH key enforcement
- 📋 **Configuration validation** and pre-deployment checks
- 🔄 **Automated backup solutions** with encryption support
- 📖 **Example configurations** for various deployment scenarios
- 💻 **Desktop client configuration guide** with OAuth settings
- 📱 **Mobile app setup instructions** for iOS and Android
- 🔧 **CLI tool configuration** with device code flow support
- 🤖 **Automatic hcloud CLI installation** with cross-platform support (macOS/Linux)
- ⏱️ **Enhanced SSH waiting with countdown timers** and server boot detection
- 🔄 **Improved retry logic** for SSH connections and server setup
- 🔧 **Interactive context management** for Hetzner Cloud API setup

### Fixed
- 🚨 **Critical: Management service crashes** due to Azure AD IdP configuration expecting client secrets in SPA mode
- 🌐 **API connection refused errors** (port 33073) caused by management service crashes
- 🔧 **TURN server IP configuration** not updating after server IP changes
- 📋 **SSH configuration and known_hosts** management for IP address changes
- 🔧 **Docker Compose detection** issues with modern Docker that includes compose as plugin
- ⚠️ **SSH verification false positives** causing unnecessary deployment warnings
- 🔧 **Enhanced management script deployment** ensuring proper script installation
- 🐛 **OAuth 400 Bad Request errors** during Azure AD authentication
- 🔧 **Nginx SPA routing issues** causing 404 errors on `/auth` callbacks
- 🚫 **PKCE vs Client Secret conflicts** in OAuth flow
- 🔐 **Token exchange failures** in Azure AD integration
- 🌐 **CORS policy errors** in browser console
- 📝 **Configuration file permission issues**
- 🔄 **Service restart failures** after configuration changes
- 📱 **Incorrect mobile/desktop redirect URIs** - now uses Microsoft default URIs
- ⏱️ **SSH connection timeout issues** during server setup
- 🔧 **Inconsistent firewall detection** reporting incorrect application status
- 📋 **Azure AD setup sequence** - Application ID URI now set before API permissions
- ⚡ **Prerequisite failures** - automatic hcloud CLI installation instead of hard exit
- 🕐 **Server boot timing** - added initial delay for proper server initialization

### Changed
- 🔧 **Azure AD configuration for SPA applications** - disabled server-side IdP management that requires client secrets
- 💾 **Docker installation method** - changed to official Docker installation for better Compose plugin support
- 🔧 **SSH verification approach** - made more lenient to reduce false positive failures
- 🌐 **IP assignment workflow** - added interactive Primary IP selection during deployment
- 📋 **Management script deployment** - improved reliability with multiple upload methods and fallbacks
- 🔄 **Updated nginx configuration** with proper `try_files` directive for SPA routing
- 🏗️ **Improved deployment script structure** with better error handling
- 📚 **Enhanced user prompts** with clearer instructions and validation
- 🎨 **Better output formatting** with colored status messages
- 🔧 **Optimized Docker configurations** for better performance and security
- 📋 **Streamlined Azure AD setup process** with step-by-step guidance for all platforms
- 🌐 **Expanded Azure AD configuration** to support both SPA and mobile/desktop platforms
- 📱 **Universal OAuth setup** with multiple redirect URIs for all client types
- 📖 **Enhanced documentation** with platform-specific configuration instructions
- 🔧 **Corrected Azure AD mobile/desktop redirect URIs** to use Microsoft default URIs
- ⚡ **Improved prerequisite checks** with automatic dependency installation
- 🕐 **Enhanced server boot waiting** with visual countdown timers
- 🔍 **Better firewall detection** with auto-application and detailed status reporting
- 📋 **Reordered Azure AD setup steps** to ensure Application ID URI is set before API permissions

### Security
- 🔒 **Proper SPA security configuration** - eliminated server-side client secret requirements preventing security vulnerabilities
- 🔧 **Secured management service** - prevented crashes that could expose security issues
- 🔒 **Implemented universal PKCE-only OAuth flow** eliminating client secret requirements for all platforms
- 🛡️ **Added comprehensive firewall rules** with UFW configuration
- 🔐 **Enhanced SSL/TLS configuration** with modern cipher suites
- 📊 **Improved security monitoring** with automated threat detection
- 🔄 **Secure backup encryption** with GPG and cloud storage integration
- 👤 **Hardened user access controls** with SSH key enforcement
- 📱 **Multi-platform security** with proper public client flow configuration
- 🔧 **Enhanced OAuth security** with platform-specific redirect URI validation
- 🔐 **Improved Azure AD configuration** using Microsoft's secure default redirect URIs
- 🛡️ **Better firewall management** with automatic application and verification

## [2.1.0] - 2025-07-12

### Added
- 🌍 **Multi-location server deployment** support
- 🔧 **Custom server type selection** during deployment
- 📱 **Mobile-friendly dashboard** improvements
- 🔄 **Automatic certificate renewal** with Let's Encrypt
- 📊 **Basic health monitoring** for NetBird services

### Fixed
- 🐛 **SSL certificate generation failures** on certain domains
- 🔧 **Docker compose service dependencies** issues
- 🌐 **DNS resolution problems** in containerized environment
- 📝 **Configuration file templating** bugs

### Changed
- 🏗️ **Improved script modularity** with better function organization
- 📚 **Updated documentation** with more detailed Azure AD setup
- 🎨 **Enhanced user interface** feedback during deployment

## [2.0.0] - 2025-07-10

### Added
- 🎉 **Complete rewrite** of deployment automation
- 🔐 **Azure AD integration** for enterprise authentication
- 🐳 **Docker Compose orchestration** for service management
- 🌐 **Nginx reverse proxy** configuration with SSL termination
- 🔧 **Hetzner Cloud API integration** for automated infrastructure provisioning
- 📋 **Interactive setup wizard** with input validation
- 🛡️ **Security best practices** implementation
- 📚 **Comprehensive documentation** and setup guides

### Changed
- 🏗️ **Migrated from manual setup** to fully automated deployment
- 🔄 **Replaced self-signed certificates** with Let's Encrypt automation
- 📦 **Updated to latest NetBird versions** with improved stability

### Removed
- ❌ **Manual configuration steps** (now automated)
- ❌ **Basic HTTP authentication** (replaced with Azure AD)
- ❌ **Static IP requirements** (now dynamic with DNS)

## [1.2.1] - 2025-06-20

### Fixed
- 🐛 **NetBird management service** startup issues
- 🔧 **Signal server connectivity** problems
- 📝 **Configuration file parsing** errors

### Security
- 🔒 **Updated base system packages** to latest security patches
- 🛡️ **Improved firewall rule specificity**

## [1.2.0] - 2025-06-15

### Added
- 🔄 **Automatic system updates** configuration
- 📊 **Basic logging** for troubleshooting
- 🔧 **Service health checks** implementation
- 📋 **Pre-deployment validation** checks

### Changed
- 🏗️ **Improved error handling** throughout the script
- 📚 **Updated setup documentation** with troubleshooting section

## [1.1.0] - 2025-06-10

### Added
- 🌐 **Custom domain support** for NetBird dashboard
- 🔐 **SSH key authentication** enforcement
- 🛡️ **Basic firewall configuration** with UFW
- 📋 **Installation prerequisites** checking

### Fixed
- 🐛 **Service startup order** dependencies
- 🔧 **Network configuration** issues in Docker environment

## [1.0.0] - 2025-06-01

### Added
- 🎉 **Initial release** of NetBird Self-Hosted Deployer
- 🏗️ **Basic deployment automation** for Hetzner Cloud
- 🐳 **Docker-based NetBird installation** with management and signal servers
- 🔧 **Manual configuration support** for basic setups
- 📚 **Initial documentation** and setup guide
- 🛡️ **Basic security configuration** with SSH access

### Features
- ✅ **Automated server provisioning** on Hetzner Cloud
- ✅ **NetBird management server** deployment
- ✅ **Signal server** configuration
- ✅ **Basic firewall rules** setup
- ✅ **SSH key management** for secure access

---

## Legend

- 🎉 **Major Features** - Significant new functionality
- ✨ **New Features** - Added functionality
- 🔧 **Improvements** - Enhanced existing features
- 🐛 **Bug Fixes** - Resolved issues
- 🔒 **Security** - Security-related changes
- 🔄 **Changes** - Modified existing functionality
- ❌ **Removed** - Deprecated or removed features
- 📚 **Documentation** - Documentation updates
- 🏗️ **Infrastructure** - Build or deployment changes

## Versioning Strategy

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

## Release Schedule

- **Major releases**: Quarterly (March, June, September, December)
- **Minor releases**: Monthly or as needed for significant features
- **Patch releases**: As needed for critical bug fixes and security updates

## Support Policy

- **Current version (2.x)**: Full support with new features and bug fixes
- **Previous major version (1.x)**: Security fixes only for 6 months after 2.0.0 release
- **Older versions**: No longer supported

For support and questions, please visit our [GitHub repository](https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer) or contact support@panoptic.ie.