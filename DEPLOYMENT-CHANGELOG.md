# NetBird Self-Hosted Deployment Enhancement Changelog

## Version 3.0.0 - 1Password SSH Integration & Modular Architecture

### New Features

#### `connect` Command (`manage-ssh-keys.sh connect`)
- **One-step colleague onboarding** — colleagues sharing a 1Password vault can run a single command to get SSH access to any NetBird server
- Lists NetBird servers from Hetzner Cloud (filtered by `managed-by=netbird-selfhosted` label)
- Interactive numbered menu with server name, IP, and status (auto-selects if only one server)
- Derives project name from server name, verifies the SSH key exists in 1Password
- Automatically configures `~/.config/1Password/ssh/agent.toml` and generates an SSH config entry
- Prints a ready-to-use `ssh -F .ssh-keys/ssh-config <server-name>` command

#### Cross-Platform 1Password Support
- New `_1p_agent_sock()` helper returns the correct 1Password SSH agent socket path per OS
  - macOS: `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`
  - Linux/WSL: `~/.1password/agent.sock`
- Replaces three previously hardcoded macOS-only paths in `ssh_generate_config()`, `ssh_configure_1p_agent()`, and `cmd_agent_config()`

#### Automatic Version Check
- New `check_for_updates()` queries the GitHub Releases API (with tags fallback) on every run
- Compares local `VERSION` against the latest release using `sort -V`
- Prompts the user to update if a newer version is available, with a one-liner install command
- Defaults to "continue" so it never blocks automation; fails silently on network errors
- Added to `deploy-netbird-selfhosted.sh`, `manage-netbird-selfhosted.sh`, and `install.sh`

#### 1Password SSH Key Management
- SSH keys stored as `sshkey` items in 1Password vaults — no local private key files
- Automatic migration of existing file-based keys to 1Password
- `agent.toml` configuration for the 1Password SSH agent
- Public key pinning via `IdentitiesOnly` to avoid `MaxAuthTries` disconnects

#### Modular Library Architecture
- Seven shared modules in `lib/`:
  - `output-helpers.sh` — colored output, prompts, version checking
  - `install-deps.sh` — dependency installation (hcloud, op, jq)
  - `ssh-manager.sh` — 1Password SSH integration
  - `entra-setup.sh` — Azure AD / Entra ID app setup
  - `hcloud-helpers.sh` — Hetzner Cloud API helpers
  - `dns-helpers.sh` — DNS record management
  - `netbird-config.sh` — NetBird configuration generation

#### One-Liner Installer
- `curl -fsSL .../install.sh | bash` downloads the toolkit and offers to start deployment

### SSH Key Management Commands
```bash
manage-ssh-keys.sh init <project> [--vault <vault>]       # Generate SSH key in 1Password
manage-ssh-keys.sh connect [--vault <vault>]               # Connect to a colleague's server
manage-ssh-keys.sh add <server> <pubkey|op://ref>          # Add a colleague's key
manage-ssh-keys.sh remove <server> <fingerprint>           # Remove a key by fingerprint
manage-ssh-keys.sh list <server>                           # List authorized keys
manage-ssh-keys.sh export-config                           # Print SSH config
manage-ssh-keys.sh setup-deploy-user <server>              # Create non-root deploy user
manage-ssh-keys.sh agent-config [--vault <vault>]          # Print agent.toml snippet
```

---

## Version 2.1.0 - Enhanced SSL & Azure AD Support

### 🚀 Major Improvements

#### SSL Certificate Management
- **Automatic SSL Certificate Verification**: Added comprehensive SSL certificate checking during deployment
- **Real-time Certificate Monitoring**: New `ssl` command in management script provides instant certificate status
- **Certificate Expiry Warnings**: Automatic alerts for certificates expiring within 30 days
- **HTTPS Connectivity Testing**: Validates both certificate existence and accessibility
- **Enhanced Error Reporting**: Clear feedback on SSL issues with troubleshooting guidance

#### Azure AD Integration Enhancements
- **Permission Error Detection**: Automatically detects Azure AD Graph API 403 errors
- **Interactive Fix Guide**: Step-by-step instructions for resolving permission issues
- **Streamlined Restart Process**: Simple command to restart services after permission fixes
- **Permission Validation**: Checks for common Azure AD integration issues

#### Enhanced Management Script
- **Health Check Dashboard**: Comprehensive system health monitoring (`health` command)
- **SSL Certificate Status**: Dedicated `ssl` command for certificate verification
- **Azure AD Troubleshooting**: Built-in `azure-fix` command with detailed instructions
- **Colored Output**: Improved readability with color-coded status messages
- **Service Monitoring**: Enhanced service status reporting with detailed container information

### 🛠️ Technical Improvements

#### Deployment Script Enhancements
- **SSL Verification Integration**: Post-deployment SSL certificate validation
- **Azure AD Instructions**: Enhanced setup guidance with specific domain configuration
- **Error Handling**: Improved error detection and recovery mechanisms
- **User Experience**: Better feedback during deployment process

#### Management Script Features
- **Domain Auto-Detection**: Automatically detects NetBird domain from configuration
- **Docker Compose Compatibility**: Supports both `docker compose` and `docker-compose`
- **Certificate Expiry Monitoring**: Proactive certificate renewal alerts
- **Log Analysis**: Intelligent log parsing for common issues

### 📋 New Commands Available

#### Management Script Commands
```bash
# Complete health check (services, SSL, Azure AD)
ssh root@<server-ip> '/root/netbird-management.sh health'

# Check SSL certificate status
ssh root@<server-ip> '/root/netbird-management.sh ssl'

# Show Azure AD permission fix instructions
ssh root@<server-ip> '/root/netbird-management.sh azure-fix'

# Enhanced service logging with filtering
ssh root@<server-ip> '/root/netbird-management.sh logs management'
```

### 🔧 Azure AD Permission Fix Process

#### Quick Fix Steps
1. **Access Azure Portal**: https://portal.azure.com
2. **Navigate to App Registrations**: Azure AD > App Registrations > Your NetBird App
3. **Add Permissions**: API permissions > + Add a permission > Microsoft Graph
4. **Grant User.Read.All**: Select "Delegated permissions" > Add "User.Read.All"
5. **Grant Admin Consent**: Click "Grant admin consent for [organization]"
6. **Restart Services**: `ssh root@<server-ip> '/root/netbird-management.sh restart'`

### 📈 Deployment Improvements

#### Pre-Deployment Checks
- ✅ Prerequisites validation
- ✅ Azure AD configuration guidance
- ✅ Domain setup instructions
- ✅ SSL certificate email validation

#### Post-Deployment Verification
- ✅ Service health monitoring
- ✅ SSL certificate validation
- ✅ Azure AD integration testing
- ✅ Firewall configuration verification
- ✅ Domain connectivity testing

### 🔍 Troubleshooting Enhancements

#### Common Issues Addressed
- **SSL Certificate Generation**: Automatic verification and troubleshooting
- **Azure AD 403 Errors**: Clear resolution steps with automated detection
- **Service Status**: Comprehensive health monitoring
- **Domain Resolution**: DNS and connectivity testing

#### Enhanced Error Messages
- **Colored Output**: Red for errors, green for success, yellow for warnings
- **Contextual Help**: Specific guidance for each type of issue
- **Command Suggestions**: Ready-to-use commands for issue resolution

### 🎯 User Experience Improvements

#### Interactive Features
- **Step-by-Step Guidance**: Clear instructions for each deployment phase
- **Real-time Feedback**: Immediate status updates during deployment
- **Error Recovery**: Helpful suggestions when issues occur
- **Command Reference**: Built-in help for all management operations

#### Documentation Integration
- **Inline Help**: Comprehensive help text in all scripts
- **Command Examples**: Ready-to-use command examples
- **Troubleshooting Guide**: Built-in troubleshooting within the tools

### 🚨 Breaking Changes
- **Management Script Location**: Enhanced script replaces original at `/root/netbird-management.sh`
- **New Command Structure**: Additional commands available (backward compatible)
- **Version Requirement**: Requires Docker Compose v2 support detection

### 🔄 Migration Notes
- **Existing Deployments**: Enhanced management script automatically replaces basic version
- **Backward Compatibility**: All existing commands continue to work
- **Configuration**: No changes required to existing NetBird configurations

### 🧪 Testing & Validation

#### Automated Tests
- ✅ SSL certificate validation
- ✅ Azure AD permission checking
- ✅ Service health monitoring
- ✅ Domain connectivity testing

#### Manual Verification
- ✅ Complete deployment workflow
- ✅ SSL certificate generation
- ✅ Azure AD integration
- ✅ Service management operations

### 📊 Performance Improvements
- **Faster SSL Checks**: Optimized certificate validation (10-second timeout)
- **Efficient Log Analysis**: Targeted log parsing for specific issues
- **Reduced Deployment Time**: Parallel verification processes
- **Resource Monitoring**: Built-in disk usage and system health checks

### 🔒 Security Enhancements
- **SSL Certificate Validation**: Ensures proper HTTPS encryption
- **Azure AD Permission Auditing**: Monitors for security-related permission issues
- **Secure Secret Handling**: Improved handling of Azure AD client secrets
- **Certificate Expiry Monitoring**: Proactive security certificate management

### 🎉 Current Status
- **Version**: 2.1.0
- **Production Ready**: ✅ Yes
- **SSL Support**: ✅ Full validation and monitoring
- **Azure AD Support**: ✅ Enhanced with error detection and resolution
- **Management Tools**: ✅ Comprehensive health monitoring

### 🔮 Future Enhancements
- **Certificate Auto-Renewal**: Automatic Let's Encrypt certificate renewal
- **Multi-Domain Support**: Support for multiple NetBird domains
- **Advanced Monitoring**: Integration with external monitoring systems
- **Backup & Restore**: Automated configuration backup and restore functionality

---

## Installation & Usage

### Quick Start
```bash
# Download and run deployment script
curl -O https://raw.githubusercontent.com/your-repo/netbird-deployment/main/deploy-netbird-selfhosted.sh
chmod +x deploy-netbird-selfhosted.sh
./deploy-netbird-selfhosted.sh
```

### Management Commands
```bash
# Check complete system health
ssh root@<server-ip> '/root/netbird-management.sh health'

# Monitor SSL certificate
ssh root@<server-ip> '/root/netbird-management.sh ssl'

# Fix Azure AD permissions
ssh root@<server-ip> '/root/netbird-management.sh azure-fix'
```

### Support & Documentation
- **NetBird Documentation**: https://docs.netbird.io/selfhosted/selfhosted-guide
- **Azure AD Setup Guide**: https://docs.netbird.io/selfhosted/identity-providers#azure-ad-microsoft-entra-id
- **Hetzner Cloud Docs**: https://docs.hetzner.com/cloud/
- **GitHub Issues**: https://github.com/netbirdio/netbird/issues

---

*This changelog documents the enhancements made to the NetBird self-hosted deployment script, focusing on SSL certificate management and Azure AD integration improvements.*