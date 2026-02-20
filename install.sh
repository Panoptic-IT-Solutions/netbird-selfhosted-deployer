#!/bin/bash

# NetBird Self-Hosted Deployer - One-Liner Installer
# Downloads and sets up the latest version of the NetBird deployment toolkit
#
# Usage: curl -fsSL https://raw.githubusercontent.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/main/install.sh | bash

set -e

VERSION="3.0.0"
REPO_URL="https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer"
ARCHIVE_URL="https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/archive/refs/heads/main.tar.gz"
INSTALL_DIR="$HOME/netbird-selfhosted-deployer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_header()  { echo -e "${PURPLE}$1${NC}"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists apt-get; then
            echo "ubuntu"
        elif command_exists yum; then
            echo "centos"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

check_requirements() {
    print_status "Checking requirements..."

    local missing=()
    command_exists curl || missing+=("curl")
    command_exists tar  || missing+=("tar")

    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        print_error "Please install them and try again."
        exit 1
    fi

    print_success "Requirements satisfied (curl, tar)"
}

setup_deployer() {
    print_status "Downloading NetBird Self-Hosted Deployer v${VERSION}..."

    # Remove existing installation if present
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Existing installation found at $INSTALL_DIR — removing..."
        rm -rf "$INSTALL_DIR"
    fi

    # Download and extract repo archive (single curl + tar, no git needed)
    curl -fsSL "$ARCHIVE_URL" | tar xz
    mv netbird-selfhosted-deployer-main "$INSTALL_DIR"

    # Make scripts executable
    chmod +x "$INSTALL_DIR"/*.sh

    print_success "Installed to: $INSTALL_DIR"
}

show_next_steps() {
    print_header "
+------------------------------------------------------------------+
|                    Installation Complete!                         |
+------------------------------------------------------------------+"

    echo
    print_success "NetBird Self-Hosted Deployer v${VERSION} is ready."
    echo
    print_status "Location: $INSTALL_DIR"
    echo
    print_header "Next Steps:"
    echo
    echo "  1. Navigate to the installation directory:"
    echo -e "     ${CYAN}cd $INSTALL_DIR${NC}"
    echo
    echo "  2. Run the deployment script:"
    echo -e "     ${CYAN}./deploy-netbird-selfhosted.sh${NC}"
    echo
    print_header "Prerequisites:"
    echo "  - Hetzner Cloud account with API token"
    echo "  - Azure AD (Entra ID) tenant with admin permissions"
    echo "  - Domain name for your NetBird dashboard"
    echo "  - 1Password CLI (op) for SSH key management"
    echo
    print_header "Documentation:"
    echo "  README  : $INSTALL_DIR/README.md"
    echo "  GitHub  : $REPO_URL"
    echo
}

offer_deployment() {
    echo
    read -p "Would you like to start the deployment now? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Starting NetBird deployment..."
        cd "$INSTALL_DIR"
        ./deploy-netbird-selfhosted.sh
    else
        print_status "Start later with:"
        echo -e "   ${CYAN}cd $INSTALL_DIR && ./deploy-netbird-selfhosted.sh${NC}"
    fi
}

main() {
    print_header "
+------------------------------------------------------------------+
|              NetBird Self-Hosted Deployer Installer               |
|                         v${VERSION}                                  |
+------------------------------------------------------------------+"

    echo
    print_status "Starting installation..."
    echo

    check_requirements
    setup_deployer
    show_next_steps
    offer_deployment
}

trap 'print_error "Installation failed. Please check the error messages above."' ERR

main "$@"
