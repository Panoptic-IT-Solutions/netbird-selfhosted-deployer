#!/bin/bash

# NetBird Self-Hosted Deployment Script with Universal Azure AD Integration
# Automatically deploys NetBird self-hosted infrastructure on Hetzner Cloud
# with Azure AD authentication for web, desktop, and mobile clients using PKCE
#
# Features:
# - Universal Azure AD configuration (web dashboard, desktop, mobile clients)
# - PKCE-based authentication (no client secrets required)
# - Automatic nginx SPA routing fix for OAuth callbacks
# - Enhanced security with modern OAuth flows
# - Complete SSL certificate management
# - Multi-platform client support

set -e

VERSION="2.2.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
SERVER_NAME_PREFIX="netbird-selfhosted"
SERVER_TYPE="cax11"  # ARM 2 vCPU, 4GB RAM
IMAGE="ubuntu-24.04"
LOCATION="nbg1"  # Nuremberg, Germany

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

print_highlight() {
    echo -e "${CYAN}$1${NC}"
}

# Function to show banner
show_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        🚀 NetBird Self-Hosted Deployment Script              ║
║                                                               ║
║     Universal Azure AD + Multi-Platform Client Support       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${CYAN}NetBird Self-Hosted Deployment Tool v$VERSION (Enhanced with SPA OAuth Fixes)${NC}"
    echo -e "${GREEN}✅ Universal OAuth Auth  ✅ Multi-Platform Support  ✅ PKCE Security${NC}"
    echo
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    local errors=0

    # Check hcloud CLI
    if ! command -v hcloud >/dev/null 2>&1; then
        print_error "hcloud CLI is not installed"
        echo "Install with: brew install hcloud"
        ((errors++))
    fi

    # Check if we can connect to Hetzner Cloud API
    if ! hcloud server list >/dev/null 2>&1; then
        print_error "Cannot connect to Hetzner Cloud API"
        echo "Run: hcloud context create <name>"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        print_error "Prerequisites not met. Please fix the issues above."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to collect customer and domain configuration first
collect_customer_and_domain_config() {
    print_header "=== Customer and Domain Configuration ==="
    echo
    echo "First, we need some basic information to customize your deployment."
    echo

    # Get customer name
    while true; do
        read -p "Enter customer name (for server naming): " CUSTOMER_NAME
        if [[ -z "$CUSTOMER_NAME" ]]; then
            print_error "Customer name cannot be empty."
            continue
        fi

        # Remove spaces and convert to lowercase for server naming
        CUSTOMER_NAME_CLEAN=$(echo "$CUSTOMER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
        SERVER_NAME="${SERVER_NAME_PREFIX}-${CUSTOMER_NAME_CLEAN}"

        echo
        print_status "Customer: $CUSTOMER_NAME"
        print_status "Server name will be: $SERVER_NAME"
        read -p "Is this correct? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            break
        fi
    done

    echo
    echo "Now, let's determine what domain you'll use for NetBird."
    echo "This will be used to generate specific Azure AD setup instructions."
    echo
    echo "Examples:"
    echo "  • netbird.yourdomain.com"
    echo "  • vpn.yourcompany.com"
    echo "  • netbird.example.org"
    echo
    print_warning "Note: You'll need to control this domain to set DNS records later."
    echo

    while true; do
        read -p "Enter your NetBird domain: " NETBIRD_DOMAIN

        if [[ -z "$NETBIRD_DOMAIN" ]]; then
            print_error "Domain cannot be empty. Please enter a valid domain."
            continue
        fi

        # Basic domain validation
        if [[ ! "$NETBIRD_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
            print_error "Please enter a valid domain name (e.g., netbird.yourdomain.com)"
            continue
        fi

        echo
        print_status "You entered: $NETBIRD_DOMAIN"
        read -p "Is this correct? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            break
        fi
    done

    read -p "Let's Encrypt Email (for SSL certificates): " LETSENCRYPT_EMAIL
    while [[ ! "$LETSENCRYPT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; do
        print_error "Please enter a valid email address"
        read -p "Let's Encrypt Email (for SSL certificates): " LETSENCRYPT_EMAIL
    done
}

# Function to show detailed Azure AD setup instructions
show_azure_setup_instructions() {
    print_header "=== Universal Azure AD Application Setup Instructions ==="
    echo
    echo "This setup configures Azure AD for ALL NetBird client types:"
    echo "🌐 Web Dashboard  💻 Desktop Clients  📱 Mobile Apps  🔧 CLI Tools"
    echo
    print_highlight "📋 Step 1: Access Azure Portal"
    echo "1. Go to https://portal.azure.com"
    echo "2. Navigate to Azure Active Directory > App Registrations"
    echo "3. Click '+ New registration'"
    echo
    print_highlight "📋 Step 2: Basic Application Settings"
    echo "1. Name: NetBird Self-Hosted (or any name you prefer)"
    echo "2. Supported account types: Accounts in this organizational directory only"
    echo "3. Redirect URI: Leave empty for now (we'll configure multiple platforms)"
    echo "4. Click 'Register'"
    echo
    print_highlight "📋 Step 3: Configure Web Dashboard Platform (Single Page Application)"
    echo "⚠️  CRITICAL: First platform for web dashboard authentication"
    echo "1. Go to Authentication section"
    echo "2. Under 'Platform configurations', if you have a 'Web' platform, REMOVE it"
    echo "3. Click '+ Add a platform' → 'Single-page application'"
    echo "4. Add these Redirect URIs for web dashboard:"
    echo "   • https://$NETBIRD_DOMAIN/auth"
    echo "   • https://$NETBIRD_DOMAIN/silent-auth"
    echo "5. Under 'Implicit grant and hybrid flows':"
    echo "   • ✅ Check 'Access tokens'"
    echo "   • ✅ Check 'ID tokens'"
    echo "6. Click 'Configure'"
    echo
    print_highlight "📋 Step 4: Configure Desktop & Mobile Clients Platform"
    echo "⚠️  REQUIRED: Essential for NetBird desktop and mobile apps"
    echo "1. Still in Authentication section, click '+ Add a platform' again"
    echo "2. Select 'Mobile and desktop applications'"
    echo "3. Add these Redirect URIs for client applications:"
    echo "   • http://localhost:53000"
    echo "   • http://localhost:54000"
    echo "   • urn:ietf:wg:oauth:2.0:oob"
    echo "4. Click 'Configure'"
    echo
    print_highlight "📋 Step 5: Configure Advanced Settings"
    echo "⚠️  REQUIRED: Enable public client flows for all platforms"
    echo "1. Still in Authentication section, scroll to 'Advanced settings'"
    echo "2. Set 'Allow public client flows' to 'Yes'"
    echo "3. Set 'Treat application as a public client' to 'Yes'"
    echo "4. Click 'Save'"
    echo
    print_highlight "📋 Step 6: API Permissions"
    echo "In API permissions section, add these permissions:"
    echo "• Microsoft Graph > User.Read (delegated) - usually already present"
    echo "• Microsoft Graph > User.Read.All (delegated) - REQUIRED"
    echo "• Microsoft Graph > offline_access (delegated)"
    echo "• Click 'Grant admin consent for [organization]' - MANDATORY"
    echo "• Verify all permissions show 'Granted for [organization]'"
    echo
    print_highlight "📋 Step 7: DO NOT CREATE CLIENT SECRET"
    echo "⚠️  IMPORTANT: For universal public client authentication, do NOT create a client secret!"
    echo "• All NetBird clients use PKCE (Proof Key for Code Exchange)"
    echo "• Client secrets are not needed and cause authentication conflicts"
    echo "• If you already created one, that's okay - we'll configure it to not use it"
    echo
    print_highlight "📋 Step 7: Collect Required Information"
    echo "From the Overview page, copy these values:"
    echo "• Application (client) ID"
    echo "• Directory (tenant) ID"
    echo "• Object ID"
    echo "• NO CLIENT SECRET NEEDED for SPA configuration"
    echo
    print_highlight "📋 Step 8: Final Verification Checklist"
    echo "⚠️  VERIFY THESE BEFORE PROCEEDING:"
    echo "• ✅ Platform type: Single-page application (NOT Web)"
    echo "• ✅ Application ID URI: api://[your-client-id]"
    echo "• ✅ API scope 'api' exists and is enabled"
    echo "• ✅ Admin consent granted for ALL permissions"
    echo "• ✅ All permissions show 'Granted for [organization]'"
    echo "• ✅ Redirect URIs configured for your domain"
    echo "• ✅ Allow public client flows: Yes"
    echo "• ✅ Access tokens and ID tokens enabled"
    echo
    print_highlight "📋 Step 8: Collect Required Information"
    echo "From the Overview page, copy these values:"
    echo "• Application (client) ID"
    echo "• Directory (tenant) ID"
    echo "• Object ID"
    echo "• NO CLIENT SECRET NEEDED for public client configuration"
    echo
    print_highlight "📋 Step 9: REQUIRED - Expose an API (Fix for AADSTS65005)"
    echo "⚠️  IMPORTANT: This step is required to prevent authentication errors!"
    echo "1. Go to 'Expose an API' in your Azure AD app"
    echo "2. Click 'Set' next to Application ID URI"
    echo "3. Accept the default: api://[your-client-id]"
    echo "4. Click 'Add a scope'"
    echo "5. Scope name: api"
    echo "6. Who can consent: Admins only"
    echo "7. Admin consent display name: Access NetBird API"
    echo "8. Admin consent description: Allows access to NetBird API"
    echo "9. State: Enabled"
    echo "10. Click 'Add scope'"
    echo
    print_highlight "📋 Step 10: Grant Admin Consent (Fix for AADSTS500011)"
    echo "⚠️  CRITICAL: Admin consent is required!"
    echo "1. Go back to 'API permissions'"
    echo "2. Click 'Grant admin consent for [your organization]'"
    echo "3. Confirm by clicking 'Yes'"
    echo "4. Ensure all permissions show 'Granted for [organization]'"
    echo
    print_highlight "📋 Step 11: Final Verification Checklist"
    echo "⚠️  VERIFY ALL PLATFORMS ARE CONFIGURED:"
    echo "• ✅ Single-page application platform with web redirect URIs"
    echo "• ✅ Mobile and desktop applications platform with client redirect URIs"
    echo "• ✅ Application ID URI: api://[your-client-id]"
    echo "• ✅ API scope 'api' exists and is enabled"
    echo "• ✅ Admin consent granted for ALL permissions"
    echo "• ✅ All permissions show 'Granted for [organization]'"
    echo "• ✅ Allow public client flows: Yes"
    echo "• ✅ Treat application as a public client: Yes"
    echo "• ✅ Access tokens and ID tokens enabled"
    echo
    echo "═══════════════════════════════════════════════════════════════════════"
    print_success "🎯 Platform Configuration Summary:"
    echo "🌐 Web Dashboard: https://$NETBIRD_DOMAIN/auth, /silent-auth"
    echo "💻 Desktop Apps: http://localhost:53000, http://localhost:54000"
    echo "📱 Mobile Apps: http://localhost:53000, http://localhost:54000"
    echo "🔧 CLI Tools: urn:ietf:wg:oauth:2.0:oob"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo
    print_warning "🔗 Useful Links:"
    echo "• Azure Portal: https://portal.azure.com"
    echo "• NetBird Azure AD Guide: https://docs.netbird.io/selfhosted/identity-providers#azure-ad-microsoft-entra-id"
    echo "• Detailed Setup Guide: Check AZURE-AD-SPA-SETUP.md in this package"
    echo
    print_success "✅ Once you have all the information, continue below!"
    echo
}

# Function to collect Azure AD configuration
collect_azure_config() {
    # First collect customer and domain configuration
    collect_customer_and_domain_config

    # Show detailed setup instructions
    show_azure_setup_instructions

    print_header "=== Azure AD Information Collection ==="
    echo
    echo "Enter the information you collected from your Azure AD application:"
    echo

    # Ask about SPA configuration (no client secret needed)
    print_warning "⚠️  IMPORTANT: For universal public client configuration, no client secret is needed"
    echo "This deployment uses PKCE (Proof Key for Code Exchange) for enhanced security."
    echo "Verify you configured BOTH platforms:"
    echo "1. Single-page application (for web dashboard)"
    echo "2. Mobile and desktop applications (for NetBird clients)"
    echo
    read -p "Did you configure BOTH platform types as instructed above? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_error "Please go back and configure your Azure AD app with BOTH platform types:"
        print_status "1. Single-page application platform for web dashboard"
        print_status "2. Mobile and desktop applications platform for NetBird clients"
        print_status "Both are required for complete NetBird functionality!"
        exit 1
    fi
    print_success "Universal platform configuration confirmed - proceeding with PKCE authentication"
    AZURE_CLIENT_SECRET=""  # Empty for public client configuration
    echo

    read -p "Azure AD Directory (tenant) ID: " AZURE_TENANT_ID
    while [[ ! "$AZURE_TENANT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; do
        print_error "Please enter a valid tenant ID (UUID format)"
        read -p "Azure AD Directory (tenant) ID: " AZURE_TENANT_ID
    done

    read -p "Azure AD Application (client) ID: " AZURE_CLIENT_ID
    while [[ ! "$AZURE_CLIENT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; do
        print_error "Please enter a valid client ID (UUID format)"
        read -p "Azure AD Application (client) ID: " AZURE_CLIENT_ID
    done

    read -p "Azure AD Object ID: " AZURE_OBJECT_ID
    while [[ ! "$AZURE_OBJECT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; do
        print_error "Please enter a valid object ID (UUID format)"
        read -p "Azure AD Object ID: " AZURE_OBJECT_ID
    done

    echo
    print_header "=== Configuration Summary ==="
    echo "Customer: $CUSTOMER_NAME"
    echo "Server Name: $SERVER_NAME"
    echo "Domain: $NETBIRD_DOMAIN"
    echo "Tenant ID: $AZURE_TENANT_ID"
    echo "Client ID: $AZURE_CLIENT_ID"
    echo "Object ID: $AZURE_OBJECT_ID"
    echo "Authentication: Universal Public Client with PKCE (no client secret)"
    echo "Let's Encrypt Email: $LETSENCRYPT_EMAIL"
    echo
    echo "Azure AD Redirect URIs configured:"
    echo "🌐 Web Dashboard:"
    echo "  • https://$NETBIRD_DOMAIN/auth"
    echo "  • https://$NETBIRD_DOMAIN/silent-auth"
    echo "💻📱 Desktop & Mobile Clients:"
    echo "  • http://localhost:53000"
    echo "  • http://localhost:54000"
    echo "  • urn:ietf:wg:oauth:2.0:oob"
    echo

    read -p "Is this information correct? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_error "Please run the script again with correct information"
        exit 1
    fi
}

# Function to create or get firewall
create_firewall() {
    print_header "=== Creating Firewall Rules ==="
    echo

    # Generate firewall name based on customer
    if [ -n "$CUSTOMER_NAME" ]; then
        FIREWALL_NAME="${CUSTOMER_NAME_CLEAN}-netbird-firewall"
    else
        FIREWALL_NAME="netbird-firewall"
    fi

    print_status "Creating firewall: $FIREWALL_NAME"
    echo "Firewall rules:"
    echo "  • SSH: TCP 22"
    echo "  • HTTP/HTTPS: TCP 80, 443"
    echo "  • NetBird Management: TCP 33073"
    echo "  • NetBird Signal: TCP 10000"
    echo "  • NetBird Relay: TCP 33080"
    echo "  • STUN/TURN: UDP 3478"
    echo "  • TURN Dynamic: UDP 49152-65535"
    echo

    # Check if firewall already exists
    if hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
        print_warning "Firewall '$FIREWALL_NAME' already exists!"
        read -p "Do you want to delete it and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deleting existing firewall..."
            hcloud firewall delete "$FIREWALL_NAME"
            print_success "Firewall deleted"
        else
            print_status "Using existing firewall"
            return 0
        fi
    fi

    # Create firewall with NetBird rules
    print_status "Creating firewall with NetBird rules..."
    hcloud firewall create \
        --name "$FIREWALL_NAME" \
        --label "managed-by=netbird-selfhosted" \
        --label "customer=${CUSTOMER_NAME_CLEAN:-default}" \
        --label "purpose=netbird-ports"

    if [ $? -eq 0 ]; then
        print_success "Firewall '$FIREWALL_NAME' created successfully"
    else
        print_error "Failed to create firewall '$FIREWALL_NAME'"
        exit 1
    fi

    # Add SSH rule
    print_status "Adding SSH rule (TCP 22)..."
    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 22 \
        --protocol tcp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "SSH access"

    # Add HTTP/HTTPS rules
    print_status "Adding HTTP/HTTPS rules (TCP 80, 443)..."
    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 80 \
        --protocol tcp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "HTTP - Let's Encrypt & Dashboard"

    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 443 \
        --protocol tcp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "HTTPS - NetBird Dashboard"

    # Add NetBird Management API rules
    print_status "Adding NetBird Management rules (TCP 33073, 10000)..."
    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 33073 \
        --protocol tcp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "NetBird Management gRPC API"

    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 10000 \
        --protocol tcp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "NetBird Signal HTTP API"

    # Add NetBird Relay rule
    print_status "Adding NetBird Relay rule (TCP 33080)..."
    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 33080 \
        --protocol tcp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "NetBird Relay gRPC API"

    # Add STUN/TURN rules
    print_status "Adding STUN/TURN rules (UDP 3478, 49152-65535)..."
    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 3478 \
        --protocol udp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "Coturn STUN server"

    hcloud firewall add-rule "$FIREWALL_NAME" \
        --direction in \
        --port 49152-65535 \
        --protocol udp \
        --source-ips 0.0.0.0/0 \
        --source-ips ::/0 \
        --description "Coturn TURN dynamic ports"

    print_success "All firewall rules configured successfully"
    print_status "Firewall '$FIREWALL_NAME' ready for server assignment"
}

# Function to ensure SSH key exists
ensure_ssh_key() {
    # Check if we have a local SSH key
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_status "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "netbird-selfhosted-$(date +%Y%m%d)"
    fi

    # Get the MD5 fingerprint of our local key (to match Hetzner format)
    local local_fingerprint=$(ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://')

    # Check if any existing SSH key matches our local key
    local existing_key=$(hcloud ssh-key list -o json | jq -r --arg fp "$local_fingerprint" '.[] | select(.fingerprint == $fp) | .name' | head -1)

    if [ -n "$existing_key" ]; then
        print_success "Using existing SSH key: $existing_key"
        SSH_KEY_NAME="$existing_key"
    else
        # Try to create a new key with a unique name
        local key_name="netbird-selfhosted-key-$(date +%s)"
        print_status "Creating new SSH key: $key_name"

        if hcloud ssh-key create --name "$key_name" --public-key-from-file ~/.ssh/id_rsa.pub >/dev/null 2>&1; then
            print_success "SSH key created successfully: $key_name"
            SSH_KEY_NAME="$key_name"
        else
            # If creation fails, try to use an existing key
            print_warning "Could not create new SSH key, using first available key"
            SSH_KEY_NAME=$(hcloud ssh-key list -o json | jq -r '.[0].name')
            if [ -n "$SSH_KEY_NAME" ] && [ "$SSH_KEY_NAME" != "null" ]; then
                print_success "Using existing SSH key: $SSH_KEY_NAME"
            else
                print_error "No SSH keys available and cannot create new one"
                return 1
            fi
        fi
    fi
}

# Function to create the server
create_server() {
    print_header "=== Creating NetBird Server ==="
    echo

    # Check if server already exists
    if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
        print_warning "Server '$SERVER_NAME' already exists!"
        read -p "Do you want to delete it and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deleting existing server..."
            hcloud server delete "$SERVER_NAME"
            print_success "Server deleted"
        else
            print_status "Using existing server"
            return 0
        fi
    fi

    print_status "Creating server '$SERVER_NAME'..."
    echo "Configuration:"
    echo "  - Name: $SERVER_NAME"
    echo "  - Type: $SERVER_TYPE (ARM 2 vCPU, 4GB RAM)"
    echo "  - Image: $IMAGE"
    echo "  - Location: $LOCATION (Nuremberg, Germany)"
    echo "  - Purpose: NetBird Self-Hosted"
    echo "  - Firewall: $FIREWALL_NAME"
    echo

    # Ensure SSH key exists
    ensure_ssh_key

    # Create firewall with NetBird ports
    create_firewall

    # Create server with firewall
    print_status "Creating server with hcloud..."
    hcloud server create \
        --name "$SERVER_NAME" \
        --type "$SERVER_TYPE" \
        --image "$IMAGE" \
        --location "$LOCATION" \
        --ssh-key "$SSH_KEY_NAME" \
        --firewall "$FIREWALL_NAME" \
        --label "managed-by=netbird-selfhosted" \
        --label "purpose=netbird-server" \
        --label "customer=${CUSTOMER_NAME_CLEAN:-default}" \
        --label "created=$(date +%Y-%m-%d)"

    if [ $? -eq 0 ]; then
        print_success "Server '$SERVER_NAME' created successfully"

        # Wait for server to be ready
        wait_for_server "$SERVER_NAME"

        # Get server IP
        SERVER_IP=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')
        print_success "Server IP: $SERVER_IP"

        # Wait for SSH to be available
        if ! wait_for_ssh "$SERVER_IP"; then
            print_warning "SSH not ready yet, but continuing with deployment..."
            print_warning "You may need to wait a few more minutes before SSH works."
            read -p "Continue anyway? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                print_error "Deployment cancelled. Server created but SSH not ready."
                print_status "You can check server status with: hcloud server describe $SERVER_NAME"
                exit 1
            fi
        fi
    else
        print_error "Failed to create server '$SERVER_NAME'"
        exit 1
    fi
}

# Function to wait for server to be ready
wait_for_server() {
    local name="$1"
    local max_attempts=60
    local attempt=0

    print_status "Waiting for server '$name' to be ready..."

    while [ $attempt -lt $max_attempts ]; do
        local status=$(hcloud server describe "$name" -o json | jq -r '.status')

        if [ "$status" = "running" ]; then
            print_success "Server is running!"
            return 0
        fi

        echo -n "."
        sleep 5
        ((attempt++))
    done

    print_error "Server failed to start within expected time"
    return 1
}

# Function to wait for SSH to be available
wait_for_ssh() {
    local server_ip="$1"
    local max_attempts=60
    local attempt=0

    print_status "Waiting for SSH to be available on $server_ip..."
    print_status "Testing SSH connection (timeout: 5 minutes)..."
    echo "Progress: [Port Check] -> [SSH Auth] -> [Success]"
    echo

    while [ $attempt -lt $max_attempts ]; do
        local progress=$((attempt * 100 / max_attempts))
        printf "\rAttempt %d/%d (%d%%) - " $((attempt + 1)) $max_attempts $progress

        # Check if port 22 is responding (macOS compatible)
        local port_open=false

        # Test with netcat (macOS compatible syntax)
        if command -v nc >/dev/null 2>&1; then
            # Use netcat with macOS compatible timeout
            if nc -z -w 5 $server_ip 22 2>/dev/null; then
                port_open=true
            fi
        fi

        # Fallback to bash TCP redirection if nc fails
        if [ "$port_open" = false ]; then
            if bash -c "exec 3<>/dev/tcp/$server_ip/22 && echo 'test' >&3 && exec 3<&-" 2>/dev/null; then
                port_open=true
            fi
        fi

        if [ "$port_open" = true ]; then
            printf "Port 22 OPEN - Testing SSH auth..."

            # Test SSH connection with error capture (macOS compatible)
            local ssh_output=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o PasswordAuthentication=no -o LogLevel=ERROR root@$server_ip "echo 'SSH_TEST_SUCCESS'" 2>&1 &)
            local ssh_pid=$!
            local ssh_exit_code=124

            # Manual timeout implementation
            (sleep 15 && kill $ssh_pid 2>/dev/null) &
            local timeout_pid=$!

            if wait $ssh_pid 2>/dev/null; then
                ssh_exit_code=$?
                kill $timeout_pid 2>/dev/null
            else
                ssh_exit_code=124  # timeout exit code
                ssh_output="Connection timeout"
            fi

            if [ $ssh_exit_code -eq 0 ] && [[ "$ssh_output" == *"SSH_TEST_SUCCESS"* ]]; then
                echo
                print_success "SSH is now available and working!"

                # Clean and add to known hosts
                print_status "Managing SSH known hosts..."
                ssh-keygen -R $server_ip >/dev/null 2>&1 || true
                ssh-keyscan -H $server_ip >> ~/.ssh/known_hosts 2>/dev/null || true
                print_success "Server added to known hosts"

                return 0
            else
                printf " AUTH FAILED (exit: $ssh_exit_code)"
                if [[ "$ssh_output" == *"Connection refused"* ]]; then
                    printf " - SSH service not ready"
                elif [[ "$ssh_output" == *"Permission denied"* ]]; then
                    printf " - Key auth failed"
                elif [[ "$ssh_output" == *"Host key verification failed"* ]]; then
                    printf " - Host key issue"
                else
                    printf " - Other: $(echo "$ssh_output" | head -1 | cut -c1-30)"
                fi
            fi
        else
            printf "Port 22 CLOSED - Server still booting..."
        fi

        echo
        sleep 5
        ((attempt++))
    done

    echo
    print_error "SSH failed to become available within expected time (5 minutes)"
    print_status "Troubleshooting information:"
    echo "  • Server IP: $server_ip"
    echo "  • Manual SSH test: ssh -v root@$server_ip"
    echo "  • Check server status: hcloud server describe $(hcloud server list -o json | jq -r --arg ip "$server_ip" '.[] | select(.public_net.ipv4.ip == $ip) | .name')"
    echo "  • Server console access: hcloud server request-console $(hcloud server list -o json | jq -r --arg ip "$server_ip" '.[] | select(.public_net.ipv4.ip == $ip) | .name')"

    print_warning "The server might need more time to boot. You can continue manually later."
    return 1
}

# Function to manually add server to known hosts
add_to_known_hosts() {
    local server_ip="$1"
    print_status "Adding $server_ip to SSH known hosts..."

    # Remove any existing entries for this IP
    ssh-keygen -R $server_ip >/dev/null 2>&1 || true

    # Add the server to known hosts
    if ssh-keyscan -H $server_ip >> ~/.ssh/known_hosts 2>/dev/null; then
        print_success "Server $server_ip added to known hosts"
    else
        print_warning "Could not add server to known hosts automatically"
        echo "You can manually add it later with: ssh-keyscan -H $server_ip >> ~/.ssh/known_hosts"
    fi
}

# Function to install NetBird self-hosted
install_netbird() {
    print_header "=== Installing NetBird Self-Hosted ==="
    echo

    local server_ip=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')

    print_status "Installing NetBird self-hosted on $SERVER_NAME ($server_ip)..."

    # Test SSH connection before proceeding with more detailed feedback
    print_status "Verifying SSH connection for installation..."

    # SSH test with macOS compatible timeout
    local ssh_test_result=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes root@$server_ip "echo 'SSH_READY_FOR_INSTALL'; whoami; uptime" 2>&1 &)
    local ssh_pid=$!
    local ssh_exit_code=124

    # Manual timeout for macOS
    (sleep 15 && kill $ssh_pid 2>/dev/null) &
    local timeout_pid=$!

    if wait $ssh_pid 2>/dev/null; then
        ssh_exit_code=$?
        kill $timeout_pid 2>/dev/null
    else
        ssh_exit_code=124
        ssh_test_result="SSH connection timeout"
    fi

    if [ $ssh_exit_code -eq 0 ] && [[ "$ssh_test_result" == *"SSH_READY_FOR_INSTALL"* ]]; then
        print_success "SSH connection verified - ready for installation"
        echo "Server info: $(echo "$ssh_test_result" | tail -2 | tr '\n' ' ')"
    else
        print_error "SSH connection failed during pre-installation check"
        echo "Exit code: $ssh_exit_code"
        echo "Output: $ssh_test_result"
        show_troubleshooting "$server_ip"

        read -p "Try to continue with installation anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled. Server is created but NetBird not installed."
            print_status "You can resume installation later when SSH is stable."
            return 1
        fi
        print_warning "Proceeding with potentially unstable SSH connection..."
    fi

    # Create the installation script
    cat > /tmp/netbird-install.sh << 'EOF'
#!/bin/bash
set -e

echo "=== NetBird Self-Hosted Installation ==="

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y curl wget git docker.io docker-compose jq

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add root to docker group (for this session)
usermod -aG docker root

# Note: Firewall rules are managed by Hetzner Cloud
# Server-level iptables/ufw not needed as firewall is applied at network level
echo "Firewall: Using Hetzner Cloud firewall (no local firewall configuration needed)"

# Detect Docker Compose command
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    echo "Using new Docker Compose syntax: docker compose"
elif docker-compose --version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    echo "Using legacy Docker Compose syntax: docker-compose"
else
    echo "ERROR: Neither 'docker compose' nor 'docker-compose' found!"
    exit 1
fi

# Create NetBird directory
mkdir -p /opt/netbird
cd /opt/netbird

# Get latest NetBird release
echo "Downloading NetBird source..."
REPO="https://github.com/netbirdio/netbird/"
LATEST_TAG=$(basename $(curl -fs -o/dev/null -w %{redirect_url} ${REPO}releases/latest))
echo "Latest version: $LATEST_TAG"

# Clone NetBird repository
git clone --depth 1 --branch $LATEST_TAG $REPO
cd netbird/infrastructure_files/

# Copy example configuration
cp setup.env.example setup.env

echo "NetBird installation files prepared"
echo "Location: /opt/netbird/netbird/infrastructure_files/"
echo "Docker Compose command: $DOCKER_COMPOSE_CMD"
EOF

    # Copy and execute the installation script with better error handling
    print_status "Copying installation script to server..."
    local copy_attempts=3
    local copy_success=false

    for ((i=1; i<=copy_attempts; i++)); do
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=30 /tmp/netbird-install.sh root@$server_ip:/tmp/ 2>/dev/null; then
            copy_success=true
            break
        else
            print_warning "Copy attempt $i/$copy_attempts failed, retrying in 10 seconds..."
            sleep 10
        fi
    done

    if [ "$copy_success" = false ]; then
        print_error "Failed to copy installation script after $copy_attempts attempts"
        print_status "SSH connection may be unstable. Manual intervention required."
        return 1
    fi
    print_success "Installation script copied successfully"

    print_status "Executing installation script on server (this may take 2-3 minutes)..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 root@$server_ip "chmod +x /tmp/netbird-install.sh && echo 'Starting installation...' && /tmp/netbird-install.sh && echo 'Installation completed!'"; then
        print_error "Installation script execution failed"
        print_status "You can manually SSH to the server and run: /tmp/netbird-install.sh"
        print_status "Check installation logs with: ssh root@$server_ip 'tail -50 /var/log/cloud-init-output.log'"
        return 1
    fi

    print_success "NetBird installation files prepared"
}

# Function to configure NetBird with Universal Azure AD authentication
configure_netbird() {
    print_header "=== Configuring NetBird with Universal Azure AD ==="
    echo

    local server_ip=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')

    print_status "Configuring NetBird with Universal Azure AD integration..."

    # Create the configuration script
    cat > /tmp/netbird-configure.sh << EOF
#!/bin/bash
set -e

cd /opt/netbird/netbird/infrastructure_files/

echo "Configuring NetBird setup.env with Universal Azure AD..."

# Create setup.env with Universal Azure AD configuration
cat > setup.env << 'CONFIG_EOF'
# NetBird Domain Configuration
NETBIRD_DOMAIN="$NETBIRD_DOMAIN"
NETBIRD_LETSENCRYPT_EMAIL="$LETSENCRYPT_EMAIL"

# Universal Azure AD Configuration (supports web, desktop, mobile clients)
NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0/.well-known/openid-configuration"
NETBIRD_USE_AUTH0=false
NETBIRD_AUTH_CLIENT_ID="$AZURE_CLIENT_ID"
NETBIRD_AUTH_SUPPORTED_SCOPES="openid profile email offline_access User.Read api://$AZURE_CLIENT_ID/api"
NETBIRD_AUTH_AUDIENCE="$AZURE_CLIENT_ID"
NETBIRD_AUTH_REDIRECT_URI="/auth"
NETBIRD_AUTH_SILENT_REDIRECT_URI="/silent-auth"
NETBIRD_AUTH_USER_ID_CLAIM="oid"
NETBIRD_TOKEN_SOURCE="idToken"

# Device Authentication (disabled for Azure AD)
NETBIRD_AUTH_DEVICE_AUTH_PROVIDER="none"

# Management Service Azure AD Integration
NETBIRD_MGMT_IDP="azure"
NETBIRD_IDP_MGMT_CLIENT_ID="$AZURE_CLIENT_ID"
NETBIRD_IDP_MGMT_CLIENT_SECRET="$AZURE_CLIENT_SECRET"
NETBIRD_IDP_MGMT_EXTRA_OBJECT_ID="$AZURE_OBJECT_ID"
NETBIRD_IDP_MGMT_EXTRA_GRAPH_API_ENDPOINT="https://graph.microsoft.com/v1.0"

# Optional: Single account mode (recommended for most deployments)
# This ensures all users join the same NetBird account/network
NETBIRD_MGMT_SINGLE_ACCOUNT_MODE=true
CONFIG_EOF

echo "Configuration file created successfully"

# Run the configuration script
echo "Running NetBird configuration script..."
chmod +x configure.sh
./configure.sh

echo "NetBird configured successfully!"
echo "Configuration files generated in: /opt/netbird/netbird/infrastructure_files/artifacts/"

# Apply OAuth SPA fixes and nginx configuration
echo "Applying OAuth SPA and nginx fixes..."

# Fix 1: Update docker-compose.yml for SPA authentication (no client secret)
echo "Updating OAuth configuration for SPA authentication..."
cd artifacts/
sed -i 's|AUTH_CLIENT_SECRET=.*|AUTH_CLIENT_SECRET=|g' docker-compose.yml

# Fix 2: Apply nginx SPA routing fix
echo "Applying nginx SPA routing fix..."
cat > /tmp/nginx-spa-fix.sh << 'NGINX_EOF'
#!/bin/bash
# Fix nginx configuration for SPA routing after container starts
sleep 10  # Wait for container to be fully up

# Find the dashboard container
DASHBOARD_CONTAINER=\$(docker ps --format "table {{.Names}}" | grep dashboard | head -1)

if [ -n "\$DASHBOARD_CONTAINER" ]; then
    echo "Applying nginx SPA routing fix to \$DASHBOARD_CONTAINER..."

    # Backup original config
    docker exec \$DASHBOARD_CONTAINER cp /etc/nginx/http.d/default.conf /etc/nginx/http.d/default.conf.backup

    # Apply SPA routing fix
    docker exec \$DASHBOARD_CONTAINER sed -i 's|try_files \$uri \$uri.html \$uri/ =404;|try_files \$uri \$uri.html \$uri/ /index.html;|g' /etc/nginx/http.d/default.conf

    # Test and reload nginx
    docker exec \$DASHBOARD_CONTAINER nginx -t && docker exec \$DASHBOARD_CONTAINER nginx -s reload

    echo "Nginx SPA routing fix applied successfully!"
else
    echo "Dashboard container not found, will apply fix after startup"
fi
NGINX_EOF

chmod +x /tmp/nginx-spa-fix.sh

echo "OAuth SPA and nginx fixes prepared"

# Create firewall configuration script
echo "Firewall configuration:"
echo "  • Using Hetzner Cloud firewall: $FIREWALL_NAME"
echo "  • All NetBird ports configured at network level"
echo "  • No local firewall configuration required"
echo "  • Rules: SSH(22), HTTP(80), HTTPS(443), Management(33073), Signal(10000), Relay(33080), STUN/TURN(3478,49152-65535)"

echo "Firewall configured for NetBird via Hetzner Cloud"
EOF

    # Execute configuration on server
    print_status "Executing NetBird SPA configuration..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "bash -s" < /tmp/netbird-configure.sh; then
        print_error "NetBird configuration failed"
        print_status "You can manually SSH and configure later"
        return 1
    fi

    print_success "NetBird configured with Universal Azure AD authentication"
}

# Function to start NetBird services
start_netbird() {
    print_header "=== Starting NetBird Services ==="
    echo

    local server_ip=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')

    print_status "Starting NetBird services..."

    # Create startup script
    cat > /tmp/netbird-start.sh << 'EOF'
#!/bin/bash
set -e

cd /opt/netbird/netbird/infrastructure_files/artifacts/

# Detect Docker Compose command
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif docker-compose --version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "ERROR: Neither 'docker compose' nor 'docker-compose' found!"
    exit 1
fi

echo "Starting NetBird services with Docker Compose ($DOCKER_COMPOSE_CMD)..."
$DOCKER_COMPOSE_CMD up -d

echo "Waiting for services to start..."
sleep 30

echo "Checking service status..."
$DOCKER_COMPOSE_CMD ps

echo "NetBird services started successfully!"

# Apply nginx SPA fix after services are up
echo "Applying nginx SPA routing fix..."
/tmp/nginx-spa-fix.sh

echo "OAuth SPA and nginx fixes applied!"

# Create enhanced management script
cat > /root/netbird-management.sh << 'MGMT_EOF'
#!/bin/bash
# Enhanced NetBird Management Script with SSL Certificate Verification
# Version: 2.1.0

COMPOSE_DIR="/opt/netbird/netbird/infrastructure_files/artifacts"
NETBIRD_CONFIG="/opt/netbird/netbird/infrastructure_files/netbird.env"

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

# Detect Docker Compose command
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# Function to get NetBird domain from config
get_netbird_domain() {
    # Try to get domain from docker-compose.yml
    if [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
        domain=$(grep "LETSENCRYPT_DOMAIN=" "$COMPOSE_DIR/docker-compose.yml" | cut -d'=' -f2 | tr -d ' ')
        if [ -n "$domain" ]; then
            echo "$domain"
            return 0
        fi
    fi

    # Fallback to netbird.env if it exists
    if [ -f "$NETBIRD_CONFIG" ]; then
        domain=$(grep "NETBIRD_DOMAIN=" "$NETBIRD_CONFIG" | cut -d'=' -f2 | tr -d '"')
        if [ -n "$domain" ]; then
            echo "$domain"
            return 0
        fi
    fi

    echo "unknown"
}

# Function to check SSL certificate
check_ssl_certificate() {
    local domain=$(get_netbird_domain)

    if [ "$domain" = "unknown" ]; then
        print_error "Cannot determine NetBird domain from configuration"
        return 1
    fi

    print_status "Checking SSL certificate for $domain..."

    # Test SSL certificate existence and validity
    if cert_info=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null); then
        if [ -n "$cert_info" ]; then
            print_success "SSL certificate is active for $domain"
            echo "$cert_info"

            # Extract expiry date for warning
            expiry_date=$(echo "$cert_info" | grep "notAfter" | cut -d'=' -f2)
            expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
            current_timestamp=$(date +%s)

            if [ -n "$expiry_timestamp" ]; then
                days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))

                if [ $days_until_expiry -lt 30 ]; then
                    print_warning "Certificate expires in $days_until_expiry days!"
                elif [ $days_until_expiry -lt 7 ]; then
                    print_error "Certificate expires in $days_until_expiry days! Renewal needed urgently!"
                else
                    print_success "Certificate is valid for $days_until_expiry more days"
                fi
            fi

            # Test HTTPS connectivity
            if timeout 10 curl -s -I "https://$domain" >/dev/null 2>&1; then
                print_success "HTTPS connectivity test passed"
            else
                print_error "HTTPS connectivity test failed"
                return 1
            fi
        else
            print_error "SSL certificate information not found"
            return 1
        fi
    else
        print_error "SSL certificate check failed - certificate may not exist or domain is unreachable"
        print_status "Common issues:"
        print_status "• DNS record not pointing to this server"
        print_status "• Certificate still being generated (check logs)"
        print_status "• Firewall blocking HTTPS traffic"
        return 1
    fi
}

# Function to check Azure AD permissions
check_azure_permissions() {
    print_status "Checking Azure AD integration..."

    # Check recent logs for Azure AD errors
    cd "$COMPOSE_DIR" || return 1

    recent_logs=$($DOCKER_COMPOSE_CMD logs --tail=50 management 2>/dev/null | grep -i "403\|permission\|graph\|azure" | tail -5)

    if echo "$recent_logs" | grep -q "403"; then
        print_error "Azure AD permission errors detected!"
        print_status "Recent permission errors:"
        echo "$recent_logs"
        echo
        print_warning "To fix Azure AD permissions:"
        print_status "1. Go to https://portal.azure.com"
        print_status "2. Navigate to Azure AD > App Registrations > Your NetBird App"
        print_status "3. Go to API permissions > + Add a permission"
        print_status "4. Select Microsoft Graph > Delegated permissions"
        print_status "5. Add: User.Read.All"
        print_status "6. Click 'Grant admin consent for [organization]'"
        print_status "7. Restart services: $0 restart"
        return 1
    elif echo "$recent_logs" | grep -q -i "azure\|graph"; then
        print_success "Azure AD integration appears to be working"
        if [ -n "$recent_logs" ]; then
            echo "Recent Azure AD activity:"
            echo "$recent_logs"
        fi
    else
        print_status "No recent Azure AD activity in logs"
    fi
}

# Function to show service health
show_health() {
    print_status "NetBird Service Health Check"
    echo "════════════════════════════════════════"

    cd "$COMPOSE_DIR" || {
        print_error "Cannot access compose directory: $COMPOSE_DIR"
        return 1
    }

    # Check service status
    print_status "Docker Compose Services:"
    $DOCKER_COMPOSE_CMD ps
    echo

    # Count running services
    running_count=$($DOCKER_COMPOSE_CMD ps --filter status=running --quiet | wc -l)
    total_count=$($DOCKER_COMPOSE_CMD ps --quiet | wc -l)

    if [ "$running_count" -eq "$total_count" ] && [ "$running_count" -gt 0 ]; then
        print_success "All services are running ($running_count/$total_count)"
    else
        print_warning "Some services may have issues ($running_count/$total_count running)"
    fi

    echo

    # Check SSL certificate
    check_ssl_certificate
    echo

    # Check Azure AD permissions
    check_azure_permissions
    echo

    # Show disk usage
    print_status "Disk Usage:"
    df -h /opt/netbird 2>/dev/null || df -h /
    echo

    # Show recent errors
    print_status "Recent Errors (last 10):"
    recent_errors=$($DOCKER_COMPOSE_CMD logs --tail=100 2>/dev/null | grep -i "error\|fail\|exception" | tail -10)
    if [ -n "$recent_errors" ]; then
        echo "$recent_errors"
    else
        print_success "No recent errors found"
    fi
}

case "$1" in
    "status")
        cd "$COMPOSE_DIR" || exit 1
        $DOCKER_COMPOSE_CMD ps
        ;;
    "health")
        show_health
        ;;
    "logs")
        cd "$COMPOSE_DIR" || exit 1
        if [ -n "$2" ]; then
            $DOCKER_COMPOSE_CMD logs -f "$2"
        else
            $DOCKER_COMPOSE_CMD logs -f
        fi
        ;;
    "restart")
        cd "$COMPOSE_DIR" || exit 1
        print_status "Restarting NetBird services..."
        $DOCKER_COMPOSE_CMD restart
        print_success "Services restarted"
        ;;
    "stop")
        cd "$COMPOSE_DIR" || exit 1
        print_status "Stopping NetBird services..."
        $DOCKER_COMPOSE_CMD stop
        print_success "Services stopped"
        ;;
    "start")
        cd "$COMPOSE_DIR" || exit 1
        print_status "Starting NetBird services..."
        $DOCKER_COMPOSE_CMD up -d
        print_success "Services started"
        ;;
    "update")
        cd "$COMPOSE_DIR" || exit 1
        print_status "Updating NetBird services..."
        $DOCKER_COMPOSE_CMD pull
        $DOCKER_COMPOSE_CMD up -d --force-recreate
        print_success "Services updated"
        ;;
    "ssl")
        check_ssl_certificate
        ;;
    "azure-fix")
        print_status "Azure AD Permission Fix Guide"
        echo "════════════════════════════════════════"
        echo "If you're seeing 403 errors, follow these steps:"
        echo
        echo "1. Go to https://portal.azure.com"
        echo "2. Navigate to Azure Active Directory > App Registrations"
        echo "3. Find your NetBird application"
        echo "4. Go to API permissions"
        echo "5. Click '+ Add a permission'"
        echo "6. Select 'Microsoft Graph' > 'Delegated permissions'"
        echo "7. Add these permissions:"
        echo "   • User.Read.All"
        echo "   • Directory.Read.All (optional)"
        echo "8. Click 'Grant admin consent for [your organization]'"
        echo "9. Wait for status to show 'Granted'"
        echo "10. Restart services: $0 restart"
        echo
        echo "After completing these steps, check logs:"
        echo "$0 logs | grep -i 'permission\\|403\\|graph'"
        ;;
    *)
        echo "Enhanced NetBird Management Script v2.2.0 (with SPA OAuth fixes)"
        echo "Usage: $0 {status|health|logs|restart|stop|start|update|ssl|azure-fix}"
        echo ""
        echo "Commands:"
        echo "  status      - Show service status"
        echo "  health      - Complete health check (services, SSL, Azure AD)"
        echo "  logs        - Show service logs (use 'logs management' for specific service)"
        echo "  restart     - Restart all services"
        echo "  stop        - Stop all services"
        echo "  start       - Start all services"
        echo "  update      - Update and restart services"
        echo "  ssl         - Check SSL certificate status"
        echo "  azure-fix   - Show Azure AD permission fix instructions"
        echo ""
        echo "Using: $DOCKER_COMPOSE_CMD"
        echo "Domain: $(get_netbird_domain)"
        ;;
esac
MGMT_EOF

chmod +x /root/netbird-management.sh

echo "Enhanced NetBird management script created at /root/netbird-management.sh"
EOF

    # Execute startup script
    print_status "Starting NetBird services..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "bash -s" < /tmp/netbird-start.sh; then
        print_error "Failed to start NetBird services"
        print_status "You can manually start services by SSH and running: /root/netbird-management.sh start"
        return 1
    fi

    print_success "NetBird services started"
}

# Function to verify SSL certificate
verify_ssl_certificate() {
    local domain="$1"
    local server_ip="$2"
    local max_attempts=30
    local attempt=0

    print_header "=== SSL Certificate Verification ==="
    print_status "Checking SSL certificate for $domain..."

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        print_status "Attempt $attempt/$max_attempts: Testing SSL certificate..."

        # Check if certificate exists and is valid
        if cert_info=$(timeout 10 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null); then
            if [ -n "$cert_info" ]; then
                print_success "SSL certificate is active!"
                echo "$cert_info"

                # Test HTTPS connectivity
                if timeout 10 curl -s -I "https://$domain" >/dev/null 2>&1; then
                    print_success "HTTPS connectivity test passed!"
                    return 0
                else
                    print_warning "Certificate exists but HTTPS connection failed"
                fi
            fi
        fi

        if [ $attempt -lt $max_attempts ]; then
            print_status "Certificate not ready yet, waiting 30 seconds..."
            sleep 30
        fi
    done

    print_error "SSL certificate verification failed after $max_attempts attempts"
    print_status "You can check certificate generation logs with:"
    print_status "ssh root@$server_ip '/root/netbird-management.sh ssl'"
    return 1
}

# Function to show Azure AD restart instructions
show_azure_restart_instructions() {
    local server_ip="$1"

    print_header "=== Azure AD Permission Fix Instructions ==="
    echo
    print_warning "If you see Azure AD Graph API permission errors (403), follow these steps:"
    echo
    print_highlight "📋 Step 1: Add Microsoft Graph Permissions"
    echo "1. Go to https://portal.azure.com"
    echo "2. Navigate to Azure Active Directory > App Registrations"
    echo "3. Find your NetBird application"
    echo "4. Go to API permissions"
    echo "5. Click '+ Add a permission'"
    echo "6. Select 'Microsoft Graph' > 'Delegated permissions'"
    echo "7. Add these permissions:"
    echo "   • User.Read.All"
    echo "   • Directory.Read.All (optional, for enhanced features)"
    echo "8. Click 'Grant admin consent for [your organization]'"
    echo "9. Wait for status to show 'Granted'"
    echo
    print_highlight "📋 Step 2: Fix API Scope Configuration (AADSTS65005)"
    echo "If you see 'scope api that doesn't exist' error:"
    echo "1. Go to your Azure AD app > Expose an API"
    echo "2. Set Application ID URI to: api://[your-client-id]"
    echo "3. Add scope named 'api' with admin consent"
    echo "4. Ensure the scope is enabled"
    echo
    print_highlight "📋 Step 3: Fix Application Consent (AADSTS500011)"
    echo "If you see 'resource principal not found' error:"
    echo "1. Go to API permissions in your Azure AD app"
    echo "2. Click 'Grant admin consent for [organization]'"
    echo "3. Confirm by clicking 'Yes'"
    echo "4. Verify all permissions show 'Granted'"
    echo
    print_highlight "📋 Step 4: Restart NetBird Management Service"
    echo "After fixing configuration, restart the management service:"
    echo
    print_status "ssh root@$server_ip '/root/netbird-management.sh restart'"
    echo
    print_highlight "📋 Step 5: Verify Fix"
    echo "Check logs for permission errors:"
    echo "ssh root@$server_ip '/root/netbird-management.sh azure-fix'"
    echo
    print_success "✅ These steps will resolve Azure AD authentication issues!"
    echo
}

# Function to show troubleshooting help
show_troubleshooting() {
    local server_ip="$1"
    print_header "🔧 SSH Troubleshooting Guide"
    echo
    echo "If SSH is not working, try these steps:"
    echo
    print_highlight "1. Check server status:"
    echo "   hcloud server describe $SERVER_NAME"
    echo "   # Status should be 'running'"
    echo
    print_highlight "2. Test network connectivity:"
    echo "   ping $server_ip"
    echo "   telnet $server_ip 22"
    echo
    print_highlight "3. Check SSH service on server:"
    echo "   hcloud server request-console $SERVER_NAME"
    echo "   # In console: systemctl status ssh"
    echo
    print_highlight "4. Manual SSH test:"
    echo "   ssh -v root@$server_ip"
    echo "   # Use -v for verbose debugging"
    echo
    print_highlight "5. Add to known hosts manually:"
    echo "   ssh-keyscan -H $server_ip >> ~/.ssh/known_hosts"
    echo
    print_highlight "6. Common fixes:"
    echo "   • Wait 2-3 more minutes for server boot"
    echo "   • Check firewall: ufw status"
    echo "   • Restart SSH: systemctl restart ssh"
    echo
}

# Function to show current known hosts for Hetzner servers
show_known_hosts() {
    print_header "🔑 Current SSH Known Hosts (Hetzner Servers)"
    echo

    if [ ! -f ~/.ssh/known_hosts ]; then
        print_warning "No known_hosts file found at ~/.ssh/known_hosts"
        return
    fi

    local hetzner_hosts=$(grep -E "(hetzner|hstgr\.cloud|srv[0-9]+\.hstgr\.cloud|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" ~/.ssh/known_hosts 2>/dev/null || true)

    if [ -z "$hetzner_hosts" ]; then
        print_warning "No Hetzner servers found in known_hosts"
    else
        echo "Hetzner servers in your SSH known_hosts:"
        echo "$hetzner_hosts" | while read -r line; do
            local ip_or_host=$(echo "$line" | cut -d' ' -f1)
            local key_type=$(echo "$line" | cut -d' ' -f2)
            echo "  • $ip_or_host ($key_type)"
        done
    fi

    echo
    print_status "To remove a server from known_hosts:"
    echo "ssh-keygen -R <server_ip_or_hostname>"
    echo
    print_status "To add current server manually:"
    echo "ssh-keyscan -H <server_ip> >> ~/.ssh/known_hosts"
}

# Function to show deployment summary
show_summary() {
    print_header "🎉 NetBird Self-Hosted Deployment Complete!"
    echo

    local server_ip=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')

    echo "═══════════════════════════════════════════════════════════════"
    echo "  NetBird Self-Hosted Server Details"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Server Name: $SERVER_NAME"
    echo "Server Type: $SERVER_TYPE (ARM 2 vCPU, 4GB RAM)"
    echo "Location: $LOCATION (Nuremberg, Germany)"
    echo "IPv4 Address: $server_ip"
    echo "SSH Access: ssh root@$server_ip"
    echo "Firewall: $FIREWALL_NAME (Hetzner Cloud managed)"
    echo
    echo "NetBird Configuration:"
    echo "  Dashboard URL: https://$NETBIRD_DOMAIN"
    echo "  Identity Provider: Azure AD"
    echo "  Management API: https://$NETBIRD_DOMAIN/api"
    echo "  Configuration: /opt/netbird/netbird/infrastructure_files/"
    echo
    echo "Azure AD SPA Integration:"
    echo "  Tenant ID: $AZURE_TENANT_ID"
    echo "  Client ID: $AZURE_CLIENT_ID"
    echo "  Authentication: PKCE (no client secret)"
    echo "  OIDC Endpoint: https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0/.well-known/openid-configuration"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🚨 CRITICAL NEXT STEPS - COMPLETE THESE NOW!"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    print_highlight "1. Configure DNS (REQUIRED - Do this first!):"
    echo "   Create an A record for your domain:"
    echo "   • Domain: $NETBIRD_DOMAIN"
    echo "   • Type: A"
    echo "   • Value: $server_ip"
    echo "   • TTL: 300 (5 minutes)"
    echo
    echo "   DNS Commands (if using command line tools):"
    echo "   # Example for Cloudflare CLI:"
    echo "   # cf-cli4 --post /zones/<zone-id>/dns_records '{\"type\":\"A\",\"name\":\"$(echo $NETBIRD_DOMAIN | cut -d. -f1)\",\"content\":\"$server_ip\"}'"
    echo
    echo "   Verification:"
    echo "   dig $NETBIRD_DOMAIN +short"
    echo "   # Should return: $server_ip"
    echo
    print_highlight "2. Verify Azure AD SPA Configuration:"
    echo "   ✅ Platform type: Single-page application (NOT Web)"
    echo "   ✅ Redirect URIs should already be configured:"
    echo "      • https://$NETBIRD_DOMAIN/auth"
    echo "      • https://$NETBIRD_DOMAIN/silent-auth"
    echo "   ✅ API permissions should be granted"
    echo "   ✅ Allow public client flows: Yes"
    echo "   ✅ Access tokens and ID tokens enabled"
    echo "   ✅ NO CLIENT SECRET (SPA uses PKCE authentication)"
    echo
    print_highlight "3. Wait for SSL Certificate (5-10 minutes after DNS):"
    echo "   Monitor certificate generation:"
    echo "   ssh root@$server_ip '/root/netbird-management.sh ssl'"
    echo
    print_highlight "4. Test DNS Resolution:"
    echo "   nslookup $NETBIRD_DOMAIN"
    echo "   # Should resolve to: $server_ip"
    echo
    print_highlight "5. Fix Azure AD SPA Authentication (if needed):"
    echo "   If you see authentication errors, follow these steps:"
    echo "   • For 400 errors with PKCE: Ensure app is configured as Single Page Application"
    echo "   • For 403 errors: Add User.Read.All permission and grant admin consent"
    echo "   • For AADSTS65005: Create API scope 'api' in 'Expose an API'"
    echo "   • For AADSTS500011: Grant admin consent for all permissions"
    echo "   • For mixed auth errors: Remove client secret, use PKCE only"
    echo "   • Always restart after changes: ssh root@$server_ip '/root/netbird-management.sh restart'"
    echo "   • Get detailed help: ssh root@$server_ip '/root/netbird-management.sh azure-fix'"
    echo
    print_highlight "6. Access NetBird Dashboard:"
    echo "   🌐 https://$NETBIRD_DOMAIN"
    echo "   (Wait for SSL certificate before accessing)"
    echo
    print_highlight "7. Server Management Commands:"
    echo "   ssh root@$server_ip"
    echo "   /root/netbird-management.sh status"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🛠️  Useful Management Commands"
    echo "═══════════════════════════════════════════════════════════════"
    echo "# Check all services status"
    echo "ssh root@$server_ip '/root/netbird-management.sh status'"
    echo
    echo "# Complete health check (services, SSL, Azure AD)"
    echo "ssh root@$server_ip '/root/netbird-management.sh health'"
    echo
    echo "# Monitor real-time logs (Ctrl+C to exit)"
    echo "ssh root@$server_ip '/root/netbird-management.sh logs'"
    echo
    echo "# Check SSL certificate status"
    echo "ssh root@$server_ip '/root/netbird-management.sh ssl'"
    echo
    echo "# Test domain connectivity"
    echo "curl -I https://$NETBIRD_DOMAIN"
    echo
    echo "# Fix Azure AD permissions (if needed)"
    echo "ssh root@$server_ip '/root/netbird-management.sh azure-fix'"
    echo
    echo "# Restart all services"
    echo "ssh root@$server_ip '/root/netbird-management.sh restart'"
    echo
    echo "# Update NetBird to latest version"
    echo "ssh root@$server_ip '/root/netbird-management.sh update'"
    echo
    echo "# Check Docker containers"
    echo "ssh root@$server_ip 'docker ps'"
    echo
    echo "# Show current known hosts"
    echo "grep -E \"(hetzner|hstgr|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\" ~/.ssh/known_hosts"
    echo
    echo "# Troubleshoot SSH issues"
    echo "ssh-keyscan -H $server_ip >> ~/.ssh/known_hosts"
    echo "ssh -v root@$server_ip  # verbose SSH debugging"
    echo
    echo "# Firewall management"
    echo "hcloud firewall list"
    echo "hcloud firewall describe $FIREWALL_NAME"
    echo "hcloud firewall apply-to-resource $FIREWALL_NAME --type server --resource $SERVER_NAME"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  💰 Cost Information & Server Management"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Monthly Cost: ~€3.79 (€3.29 CAX11 server + €0.50 IPv4)"
    echo "Daily Cost: ~€0.13"
    echo
    echo "Cost Management:"
    echo "• Stop server (keeps data): hcloud server poweroff $SERVER_NAME"
    echo "• Start server: hcloud server poweron $SERVER_NAME"
    echo "• Delete permanently: hcloud server delete $SERVER_NAME"
    echo "• Delete firewall: hcloud firewall delete $FIREWALL_NAME"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  📞 Support & Documentation"
    echo "═══════════════════════════════════════════════════════════════"
    echo "• NetBird Documentation: https://docs.netbird.io/"
    echo "• Azure AD Integration: https://docs.netbird.io/selfhosted/identity-providers#azure-ad-microsoft-entra-id"
    echo "• Hetzner Cloud: https://docs.hetzner.com/cloud/"
    echo "• Issues/Support: https://github.com/netbirdio/netbird/issues"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🔧 Azure AD SPA Troubleshooting"
    echo "═══════════════════════════════════════════════════════════════"
    echo "If you encounter Azure AD authentication errors, follow these steps:"
    echo
    echo "1. Fix SPA Configuration (Fixes 400 Bad Request with PKCE):"
    echo "   ⚠️  MOST COMMON ISSUE: Mixed authentication methods"
    echo "   • Portal: https://portal.azure.com"
    echo "   • Go to: Azure AD > App Registrations > Your NetBird App"
    echo "   • Go to: Authentication section"
    echo "   • Remove any 'Web' platform configuration"
    echo "   • Ensure only 'Single-page application' platform exists"
    echo "   • Redirect URIs: https://$NETBIRD_DOMAIN/auth and /silent-auth"
    echo "   • Enable: Access tokens and ID tokens"
    echo "   • Set: Allow public client flows = Yes"
    echo "   • DO NOT use client secrets with SPA configuration"
    echo
    echo "2. Add Microsoft Graph Permissions (Fixes 403 errors):"
    echo "   • In same app: API permissions > + Add a permission"
    echo "   • Select: Microsoft Graph > Delegated permissions"
    echo "   • Add: User.Read.All"
    echo "   • Click: Grant admin consent for [organization]"
    echo
    echo "3. Fix API Scope Configuration (Fixes AADSTS65005):"
    echo "   • Go to Azure AD app > Expose an API"
    echo "   • Set Application ID URI: api://[your-client-id]"
    echo "   • Add scope 'api' with admin consent"
    echo "   • Ensure scope is enabled"
    echo
    echo "4. Fix Application Consent (Fixes AADSTS500011):"
    echo "   • Go to API permissions"
    echo "   • Click 'Grant admin consent for [organization]'"
    echo "   • Confirm and verify all permissions are granted"
    echo "   • Wait for consent status to update"
    echo
    echo "5. Restart NetBird Services:"
    echo "   ssh root@$server_ip '/root/netbird-management.sh restart'"
    echo
    echo "6. Verify OAuth Flow:"
    echo "   • Check nginx SPA routing: curl -I https://$NETBIRD_DOMAIN/auth"
    echo "   • Should return 200 OK, not 404"
    echo "   • Access: https://$NETBIRD_DOMAIN"
    echo "   • Try to sign in with Azure AD"
    echo "   • Check for PKCE/token errors in browser dev tools"
    echo
    echo "7. Common Error Fixes:"
    echo "   • 400 Bad Request: Configure as SPA, remove client secret usage"
    echo "   • 404 on /auth: nginx SPA routing fixed automatically by this script"
    echo "   • Token exchange failed: Ensure PKCE-only authentication"
    echo "   • Check logs: ssh root@$server_ip '/root/netbird-management.sh logs | grep -i error'"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  📱 Client Configuration Instructions"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Your Azure AD app is configured for ALL NetBird client types:"
    echo
    print_highlight "🌐 Web Dashboard Access:"
    echo "1. Complete DNS configuration above first"
    echo "2. Wait for SSL certificate (5-10 minutes)"
    echo "3. Access: https://$NETBIRD_DOMAIN"
    echo "4. Click 'Sign in with Microsoft'"
    echo "5. Complete Azure AD authentication"
    echo
    print_highlight "💻 Desktop Client Configuration:"
    echo "Download NetBird desktop clients:"
    echo "• Windows: https://github.com/netbirdio/netbird/releases"
    echo "• macOS: https://github.com/netbirdio/netbird/releases"
    echo "• Linux: https://github.com/netbirdio/netbird/releases"
    echo
    echo "Desktop client settings:"
    echo "• Management URL: https://$NETBIRD_DOMAIN"
    echo "• Admin URL: https://$NETBIRD_DOMAIN"
    echo "• SSO Provider: Azure AD / Microsoft Entra ID"
    echo "• Client ID: $AZURE_CLIENT_ID"
    echo "• Tenant ID: $AZURE_TENANT_ID"
    echo "• Authority: https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0"
    echo
    echo "Desktop authentication flow:"
    echo "1. Install and open NetBird desktop client"
    echo "2. Enter Management URL: https://$NETBIRD_DOMAIN"
    echo "3. Click 'Sign in with SSO'"
    echo "4. Browser will open for Azure AD authentication"
    echo "5. Complete login and return to desktop client"
    echo
    print_highlight "📱 Mobile App Configuration:"
    echo "Download NetBird mobile apps:"
    echo "• iOS: Search 'NetBird' in App Store"
    echo "• Android: Search 'NetBird' in Google Play Store"
    echo
    echo "Mobile app settings:"
    echo "• Management URL: https://$NETBIRD_DOMAIN"
    echo "• SSO Provider: Azure AD / Microsoft Entra ID"
    echo "• Client ID: $AZURE_CLIENT_ID"
    echo "• Tenant ID: $AZURE_TENANT_ID"
    echo
    echo "Mobile authentication flow:"
    echo "1. Install and open NetBird mobile app"
    echo "2. Tap 'Configure manually' or 'Add server'"
    echo "3. Enter Management URL: https://$NETBIRD_DOMAIN"
    echo "4. Select 'Azure AD' as SSO provider"
    echo "5. Enter Client ID and Tenant ID"
    echo "6. Tap 'Sign in with SSO'"
    echo "7. Complete authentication in in-app browser"
    echo
    print_highlight "🔧 CLI Tools Configuration:"
    echo "Install NetBird CLI:"
    echo "• Linux/macOS: curl -fsSL https://pkgs.netbird.io/install.sh | sh"
    echo "• Windows: Download from GitHub releases"
    echo
    echo "CLI authentication:"
    echo "netbird login --management-url https://$NETBIRD_DOMAIN \\"
    echo "              --sso-provider azure \\"
    echo "              --client-id $AZURE_CLIENT_ID \\"
    echo "              --tenant-id $AZURE_TENANT_ID"
    echo
    print_highlight "🛠️ Advanced Client Configuration:"
    echo "For custom integrations or advanced setups:"
    echo
    echo "OAuth Configuration:"
    echo "• Authority: https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0"
    echo "• Client ID: $AZURE_CLIENT_ID"
    echo "• Audience: $AZURE_CLIENT_ID"
    echo "• Scopes: openid profile email offline_access User.Read api://$AZURE_CLIENT_ID/api"
    echo "• Token Endpoint: https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token"
    echo "• User ID Claim: oid"
    echo "• Redirect URIs:"
    echo "  - Web: https://$NETBIRD_DOMAIN/auth, https://$NETBIRD_DOMAIN/silent-auth"
    echo "  - Desktop: http://localhost:53000, http://localhost:54000"
    echo "  - CLI: urn:ietf:wg:oauth:2.0:oob"
    echo
    print_highlight "🔍 Client Troubleshooting:"
    echo "Common client issues and solutions:"
    echo
    echo "1. Desktop client authentication fails:"
    echo "   • Verify Management URL is correct"
    echo "   • Check Azure AD redirect URIs include localhost ports"
    echo "   • Ensure 'Allow public client flows' is enabled"
    echo "   • Try clearing client cache/data"
    echo
    echo "2. Mobile app won't connect:"
    echo "   • Verify SSL certificate is working on web dashboard first"
    echo "   • Check mobile app has latest version"
    echo "   • Ensure Azure AD mobile platform is configured"
    echo "   • Try switching between WiFi and mobile data"
    echo
    echo "3. CLI authentication issues:"
    echo "   • Check CLI version: netbird version"
    echo "   • Verify Azure AD permissions are granted"
    echo "   • Try device code flow if localhost redirect fails"
    echo "   • Check network connectivity to management server"
    echo
    echo "4. All clients fail to authenticate:"
    echo "   • Check web dashboard authentication first"
    echo "   • Verify Azure AD admin consent is granted"
    echo "   • Ensure API scope 'api' exists and is enabled"
    echo "   • Check NetBird management server logs"
    echo
    echo "═══════════════════════════════════════════════════════════════"

    print_success "🎉 NetBird self-hosted deployment completed successfully!"
    echo
    print_warning "⚠️  IMPORTANT: Complete DNS configuration above before accessing the dashboard!"
    echo
    print_highlight "🌐 Your NetBird URL will be: https://$NETBIRD_DOMAIN"
    echo
    print_success "📱 All client types (web, desktop, mobile, CLI) are now configured!"
    print_status "Refer to the client configuration instructions above for setup details."
}

# Function to run post-deployment checks
post_deployment_checks() {
    print_header "=== Post-Deployment Verification ==="
    echo

    local server_ip=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')

    print_status "Running post-deployment checks..."

    # Check if services are running
    print_status "Checking NetBird services..."
    local running_count=$(ssh -o StrictHostKeyChecking=no root@$server_ip "cd /opt/netbird/netbird/infrastructure_files/artifacts/ && if docker compose version >/dev/null 2>&1; then docker compose ps --filter status=running --quiet | wc -l; else docker-compose ps --filter status=running --quiet | wc -l; fi" 2>/dev/null || echo "0")
    if [ "$running_count" -ge "4" ]; then
        print_success "All NetBird services are running ($running_count containers)"
    else
        print_warning "Some services might not be running correctly ($running_count/5 containers)"
        print_status "Check logs with: ssh root@$server_ip '/root/netbird-management.sh logs'"
    fi

    # Check firewall status
    print_status "Checking firewall configuration..."
    if hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
        local firewall_resources=$(hcloud firewall describe "$FIREWALL_NAME" -o json | jq -r '.resources[]?.server.name' 2>/dev/null | grep "$SERVER_NAME" || echo "")
        if [ -n "$firewall_resources" ]; then
            print_success "Firewall '$FIREWALL_NAME' is properly applied to server"
            local rule_count=$(hcloud firewall describe "$FIREWALL_NAME" -o json | jq '.rules | length' 2>/dev/null || echo "0")
            print_status "Firewall has $rule_count rules configured"
        else
            print_warning "Firewall '$FIREWALL_NAME' exists but not applied to server"
        fi
    else
        print_error "Firewall '$FIREWALL_NAME' not found"
    fi

    # Check if ports are open
    print_status "Checking if required ports are accessible..."

    # Test HTTP port (for Let's Encrypt)
    if timeout 5 bash -c "echo >/dev/tcp/$server_ip/80" 2>/dev/null; then
        print_success "Port 80 (HTTP) is accessible"
    else
        print_warning "Port 80 (HTTP) is not accessible"
    fi

    # Test HTTPS port
    if timeout 5 bash -c "echo >/dev/tcp/$server_ip/443" 2>/dev/null; then
        print_success "Port 443 (HTTPS) is accessible"
    else
        print_warning "Port 443 (HTTPS) is not accessible"
    fi

    # Verify SSL certificate
    verify_ssl_certificate "$NETBIRD_DOMAIN" "$server_ip"

    echo
    print_status "Verification complete. Check the summary above for next steps."

    # Show Azure AD restart instructions if needed
    show_azure_restart_instructions "$server_ip"
}

# Function to show usage
show_usage() {
    cat << EOF
NetBird Self-Hosted Deployment Script v2.2.0 (Enhanced with SPA OAuth)

Usage: $0 [options]

Options:
  --customer <name>      Customer name (for server naming)
  --domain <domain>      NetBird domain (e.g., netbird.yourdomain.com)
  --tenant-id <id>       Azure AD Tenant ID
  --client-id <id>       Azure AD Application (client) ID
  --client-secret <secret> Azure AD Client Secret (not needed for SPA config)
  --object-id <id>       Azure AD Object ID
  --email <email>        Let's Encrypt email
  --server-name <name>   Custom server name (default: netbird-selfhosted-<customer>)
  --server-type <type>   Server type (default: cax11)
  --location <loc>       Server location (default: nbg1)
  --help, -h            Show this help message

Examples:
  # Interactive mode (recommended)
  $0

  # Non-interactive mode
  ./deploy-netbird-selfhosted.sh --customer "Acme Corp" \
     --domain netbird.company.com \
     --tenant-id "12345678-1234-1234-1234-123456789012" \
     --client-id "87654321-4321-4321-4321-210987654321" \
     --client-secret "your-secret-here" \
     --object-id "11111111-2222-3333-4444-555555555555" \
     --email admin@company.com

What this script creates:
  • Hetzner Cloud server with NetBird self-hosted
  • Customer-specific firewall with all NetBird ports configured
  • Azure AD SPA integration with PKCE authentication (secure, no client secrets)
  • Automatic nginx SPA routing fix for OAuth callbacks
  • SSL certificates via Let's Encrypt with automatic verification
  • Enhanced management script with SSL and Azure AD monitoring
  • Complete Docker-based NetBird infrastructure with OAuth fixes

For more information:
  • NetBird Documentation: https://docs.netbird.io/selfhosted/selfhosted-guide
  • Azure AD Setup: https://docs.netbird.io/selfhosted/identity-providers#azure-ad-microsoft-entra-id
EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer)
                CUSTOMER_NAME="$2"
                shift 2
                ;;
            --domain)
                NETBIRD_DOMAIN="$2"
                shift 2
                ;;
            --tenant-id)
                AZURE_TENANT_ID="$2"
                shift 2
                ;;
            --client-id)
                AZURE_CLIENT_ID="$2"
                shift 2
                ;;
            --client-secret)
                AZURE_CLIENT_SECRET="$2"
                shift 2
                ;;
            --object-id)
                AZURE_OBJECT_ID="$2"
                shift 2
                ;;
            --email)
                LETSENCRYPT_EMAIL="$2"
                shift 2
                ;;
            --server-name)
                SERVER_NAME="$2"
                shift 2
                ;;
            --server-type)
                SERVER_TYPE="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Show banner
    show_banner

    # Check prerequisites
    check_prerequisites

    # Collect Azure AD configuration if not provided via command line
    if [ -z "$NETBIRD_DOMAIN" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || [ -z "$AZURE_OBJECT_ID" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
        collect_azure_config
    fi

    # Set server name if not already set
    if [ -z "$SERVER_NAME" ]; then
        if [ -n "$CUSTOMER_NAME" ]; then
            CUSTOMER_NAME_CLEAN=$(echo "$CUSTOMER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
            SERVER_NAME="${SERVER_NAME_PREFIX}-${CUSTOMER_NAME_CLEAN}"
        else
            SERVER_NAME="$SERVER_NAME_PREFIX"
        fi
    fi

    # Validate configuration (note: client secret not required for SPA)
    if [ -z "$NETBIRD_DOMAIN" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_OBJECT_ID" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
        print_error "Missing required configuration. Please provide all Azure AD details."
        exit 1
    fi

    print_header "=== Deployment Summary ==="
    echo "Customer: ${CUSTOMER_NAME:-N/A}"
    echo "Server: $SERVER_NAME ($SERVER_TYPE, $LOCATION)"
    echo "Domain: $NETBIRD_DOMAIN"
    echo "Identity Provider: Azure AD (SPA with PKCE)"
    echo "Authentication: No client secret (PKCE-only)"
    echo "Firewall: $FIREWALL_NAME"
    echo "Estimated cost: ~€3.79/month"
    echo

    read -p "Proceed with deployment? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi

    # Execute deployment steps
    create_server
    install_netbird
    configure_netbird
    start_netbird
    post_deployment_checks
    show_summary

    # Show known hosts for reference
    show_known_hosts

    # Cleanup temporary files
    rm -f /tmp/netbird-*.sh
}

# Run main function with all arguments
main "$@"
