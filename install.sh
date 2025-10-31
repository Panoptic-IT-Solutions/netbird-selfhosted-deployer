#!/bin/bash

# NetBird Self-Hosted Deployer - One-Click Installer
# Downloads and runs the latest version of the NetBird deployment script
#
# Usage: curl -fsSL https://raw.githubusercontent.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/main/install.sh | bash

set -e

VERSION="2.3.0"
REPO_URL="https://github.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer"
RAW_URL="https://raw.githubusercontent.com/Panoptic-IT-Solutions/netbird-selfhosted-deployer/main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}$1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS
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

# Function to install dependencies
install_dependencies() {
    local os=$(detect_os)

    print_status "Installing dependencies for $os..."

    case $os in
        ubuntu)
            if ! command_exists curl; then
                sudo apt-get update
                sudo apt-get install -y curl
            fi
            if ! command_exists git; then
                sudo apt-get install -y git
            fi
            if ! command_exists unzip; then
                sudo apt-get install -y unzip
            fi
            ;;
        centos)
            if ! command_exists curl; then
                sudo yum install -y curl
            fi
            if ! command_exists git; then
                sudo yum install -y git
            fi
            if ! command_exists unzip; then
                sudo yum install -y unzip
            fi
            ;;
        macos)
            if ! command_exists brew; then
                print_error "Homebrew is required on macOS. Please install it first: https://brew.sh/"
                exit 1
            fi
            if ! command_exists curl; then
                brew install curl
            fi
            if ! command_exists git; then
                brew install git
            fi
            ;;
        *)
            print_warning "Unsupported OS. Please ensure curl, git, and unzip are installed."
            ;;
    esac
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."

    # Check for required commands
    local missing_commands=()

    if ! command_exists curl; then
        missing_commands+=("curl")
    fi

    if ! command_exists git; then
        missing_commands+=("git")
    fi

    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_warning "Missing required commands: ${missing_commands[*]}"
        print_status "Attempting to install dependencies..."
        install_dependencies
    fi

    print_success "System requirements satisfied"
}

# Function to download and setup the deployer
setup_deployer() {
    local install_dir="$HOME/netbird-selfhosted-deployer"

    print_status "Setting up NetBird Self-Hosted Deployer v$VERSION..."

    # Remove existing installation if present
    if [ -d "$install_dir" ]; then
        print_warning "Existing installation found. Removing..."
        rm -rf "$install_dir"
    fi

    # Create installation directory
    mkdir -p "$install_dir"
    cd "$install_dir"

    # Download main deployment script
    print_status "Downloading deployment script..."
    curl -fsSL "$RAW_URL/deploy-netbird-selfhosted.sh" -o deploy-netbird-selfhosted.sh
    chmod +x deploy-netbird-selfhosted.sh

    # Download Azure AD setup guide
    print_status "Downloading Azure AD setup guide..."
    curl -fsSL "$RAW_URL/AZURE-AD-SPA-SETUP.md" -o AZURE-AD-SPA-SETUP.md

    # Download README
    print_status "Downloading README..."
    curl -fsSL "$RAW_URL/README.md" -o README.md

    print_success "NetBird Self-Hosted Deployer installed to: $install_dir"
}

# Function to display next steps
show_next_steps() {
    local install_dir="$HOME/netbird-selfhosted-deployer"

    print_header "
╔══════════════════════════════════════════════════════════════════╗
║                    Installation Complete!                       ║
╚══════════════════════════════════════════════════════════════════╝"

    echo
    print_success "NetBird Self-Hosted Deployer v$VERSION has been installed successfully!"
    echo
    print_status "Installation Location: $install_dir"
    echo
    print_header "Next Steps:"
    echo
    echo "1. Navigate to the installation directory:"
    echo -e "   ${CYAN}cd $install_dir${NC}"
    echo
    echo "2. Run the deployment script (includes Azure AD setup guidance):"
    echo -e "   ${CYAN}./deploy-netbird-selfhosted.sh${NC}"
    echo
    print_header "Prerequisites Required:"
    echo "✓ Hetzner Cloud account with API token"
    echo "✓ Azure AD tenant with admin permissions"
    echo "✓ Domain name for your NetBird dashboard"
    echo
    print_header "Documentation:"
    echo "• README: $install_dir/README.md"
    echo "• Azure AD Setup: $install_dir/AZURE-AD-SPA-SETUP.md"
    echo "• GitHub Repository: $REPO_URL"
    echo
    print_warning "Make sure to review all prerequisites before running the deployment!"
    echo
}

# Function to offer immediate deployment
offer_deployment() {
    echo
    read -p "Would you like to start the deployment now? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Starting NetBird deployment..."
        cd "$HOME/netbird-selfhosted-deployer"
        ./deploy-netbird-selfhosted.sh
    else
        print_status "Deployment can be started later by running:"
        echo -e "   ${CYAN}cd $HOME/netbird-selfhosted-deployer && ./deploy-netbird-selfhosted.sh${NC}"
    fi
}

# Main installation function
main() {
    print_header "
╔══════════════════════════════════════════════════════════════════╗
║              NetBird Self-Hosted Deployer Installer             ║
║                            Version $VERSION                            ║
╚══════════════════════════════════════════════════════════════════╝"

    echo
    print_status "Starting installation process..."
    echo

    # Check system requirements
    check_requirements

    # Setup the deployer
    setup_deployer

    # Show next steps
    show_next_steps

    # Offer immediate deployment
    offer_deployment
}

# Error handling
trap 'print_error "Installation failed. Please check the error messages above."' ERR

# Run main function
main "$@"
