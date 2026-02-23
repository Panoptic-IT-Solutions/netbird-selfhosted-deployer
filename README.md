# NetBird Self-Hosted Deployer

![Version](https://img.shields.io/badge/version-3.0.1-blue)

Automated deployment of [NetBird](https://netbird.io/) self-hosted infrastructure on Hetzner Cloud with Azure AD (Entra ID) authentication and 1Password SSH key management.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/main/install.sh | bash
```

This downloads the toolkit to `~/netbird-selfhosted-deployer` and offers to start deployment immediately.

## Prerequisites

- **Hetzner Cloud** account with a Read & Write API token
- **Azure AD (Entra ID)** tenant with admin permissions
- **Domain name** pointed at your NetBird server (A record)
- **1Password CLI** (`op`) configured for SSH key management

## What's Included

| File | Purpose |
|------|---------|
| `deploy-netbird-selfhosted.sh` | Main deployment script |
| `manage-netbird-selfhosted.sh` | Server management (start/stop/ssh/logs) |
| `manage-ssh-keys.sh` | SSH key management for team members |
| `install.sh` | One-liner installer |
| `lib/` | Shared libraries (7 modules) |
| `templates/` | NetBird configuration templates |

## Usage

### Deploy a new NetBird server

```bash
cd ~/netbird-selfhosted-deployer
./deploy-netbird-selfhosted.sh
```

The script will guide you through:
1. Hetzner Cloud CLI setup and API token configuration
2. Azure AD / Entra ID app registration (SPA with PKCE)
3. Server provisioning (Ubuntu 24.04, ARM, Nuremberg)
4. DNS configuration and SSL certificates
5. NetBird installation and configuration

### Manage an existing server

```bash
./manage-netbird-selfhosted.sh info      # Server details
./manage-netbird-selfhosted.sh ssh       # SSH connection
./manage-netbird-selfhosted.sh start     # Power on
./manage-netbird-selfhosted.sh stop      # Power off
./manage-netbird-selfhosted.sh restart   # Reboot
./manage-netbird-selfhosted.sh delete    # Remove server
```

### Manage SSH keys for colleagues

```bash
./manage-ssh-keys.sh connect                          # Set up SSH access to a colleague's server (interactive)
./manage-ssh-keys.sh init <project> --vault Netbird    # Generate SSH key in 1Password
./manage-ssh-keys.sh add <server> /path/to/key.pub     # Add a colleague's public key to a server
./manage-ssh-keys.sh remove <server> <fingerprint>     # Remove a key by fingerprint
./manage-ssh-keys.sh list <server>                     # List authorized keys on a server
```

## Architecture

```
lib/
  output-helpers.sh     # Colored output, headers, prompts
  install-deps.sh       # Dependency installation (hcloud, op, jq)
  ssh-manager.sh        # 1Password SSH key integration
  entra-setup.sh        # Azure AD / Entra ID app setup
  hcloud-helpers.sh     # Hetzner Cloud API helpers
  dns-helpers.sh        # DNS record management
  netbird-config.sh     # NetBird configuration generation
```

## What's New in v3.0.0

- **1Password SSH integration** — SSH keys managed via `op` CLI, no local key files
- **`connect` command** — one-step SSH setup for colleagues sharing a 1Password vault: lists Hetzner servers, configures `agent.toml` and SSH config automatically
- **Cross-platform support** — 1Password agent socket resolved automatically on macOS, Linux, and WSL
- **Automatic update check** — deploy, manage, and install scripts check GitHub for newer releases on startup
- **Modular library architecture** — shared `lib/` modules instead of monolithic scripts
- **One-liner installer** — single `curl | bash` to get started
- **Template-based config** — NetBird YAML templates in `templates/`
- **Simplified management** — unified `manage-netbird-selfhosted.sh` for all server operations

## License

MIT
