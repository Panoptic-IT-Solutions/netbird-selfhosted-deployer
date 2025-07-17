# Changelog

All notable changes to the NetBird Self-Hosted Deployer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2024-01-15

### Added
- ✨ **Azure AD SPA (Single Page Application) support** with PKCE authentication flow
- 🔧 **One-click installer script** for easy deployment
- 📚 **Comprehensive documentation suite** including troubleshooting and security guides
- 🛡️ **Enhanced security configurations** with fail2ban and UFW firewall
- 📊 **Advanced monitoring and logging** capabilities
- 🌐 **Multi-region deployment support** for global organizations
- 🔒 **Security hardening features** including automatic updates and SSH key enforcement
- 📋 **Configuration validation** and pre-deployment checks
- 🔄 **Automated backup solutions** with encryption support
- 📖 **Example configurations** for various deployment scenarios

### Fixed
- 🐛 **OAuth 400 Bad Request errors** during Azure AD authentication
- 🔧 **Nginx SPA routing issues** causing 404 errors on `/auth` callbacks
- 🚫 **PKCE vs Client Secret conflicts** in OAuth flow
- 🔐 **Token exchange failures** in Azure AD integration
- 🌐 **CORS policy errors** in browser console
- 📝 **Configuration file permission issues**
- 🔄 **Service restart failures** after configuration changes

### Changed
- 🔄 **Updated nginx configuration** with proper `try_files` directive for SPA routing
- 🏗️ **Improved deployment script structure** with better error handling
- 📚 **Enhanced user prompts** with clearer instructions and validation
- 🎨 **Better output formatting** with colored status messages
- 🔧 **Optimized Docker configurations** for better performance and security
- 📋 **Streamlined Azure AD setup process** with step-by-step guidance

### Security
- 🔒 **Implemented PKCE-only OAuth flow** eliminating client secret requirements
- 🛡️ **Added comprehensive firewall rules** with UFW configuration
- 🔐 **Enhanced SSL/TLS configuration** with modern cipher suites
- 📊 **Improved security monitoring** with automated threat detection
- 🔄 **Secure backup encryption** with GPG and cloud storage integration
- 👤 **Hardened user access controls** with SSH key enforcement

## [2.1.0] - 2023-12-10

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

## [2.0.0] - 2023-11-15

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

## [1.2.1] - 2023-10-20

### Fixed
- 🐛 **NetBird management service** startup issues
- 🔧 **Signal server connectivity** problems
- 📝 **Configuration file parsing** errors

### Security
- 🔒 **Updated base system packages** to latest security patches
- 🛡️ **Improved firewall rule specificity**

## [1.2.0] - 2023-10-05

### Added
- 🔄 **Automatic system updates** configuration
- 📊 **Basic logging** for troubleshooting
- 🔧 **Service health checks** implementation
- 📋 **Pre-deployment validation** checks

### Changed
- 🏗️ **Improved error handling** throughout the script
- 📚 **Updated setup documentation** with troubleshooting section

## [1.1.0] - 2023-09-15

### Added
- 🌐 **Custom domain support** for NetBird dashboard
- 🔐 **SSH key authentication** enforcement
- 🛡️ **Basic firewall configuration** with UFW
- 📋 **Installation prerequisites** checking

### Fixed
- 🐛 **Service startup order** dependencies
- 🔧 **Network configuration** issues in Docker environment

## [1.0.0] - 2023-09-01

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