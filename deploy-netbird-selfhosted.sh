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
CUSTOM_IP=""  # Will be set from command line argument

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install hcloud CLI automatically
install_hcloud_cli() {
    print_status "Installing hcloud CLI..."

    # Detect OS and install accordingly
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            print_status "Installing via Homebrew..."
            brew install hcloud
        else
            print_error "Homebrew not found! Please install Homebrew first:"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo "  Then run this script again"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        print_status "Downloading hcloud CLI for Linux..."

        # Get latest release URL
        LATEST_URL=$(curl -s https://api.github.com/repos/hetznercloud/cli/releases/latest | grep "browser_download_url.*linux-amd64.tar.gz" | cut -d '"' -f 4)

        if [ -z "$LATEST_URL" ]; then
            print_error "Could not fetch latest release URL"
            exit 1
        fi

        # Create temp directory
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"

        # Download and extract
        curl -L "$LATEST_URL" -o hcloud.tar.gz
        tar xzf hcloud.tar.gz

        # Install to /usr/local/bin
        sudo mv hcloud /usr/local/bin/
        sudo chmod +x /usr/local/bin/hcloud

        # Cleanup
        cd - > /dev/null
        rm -rf "$TEMP_DIR"

        print_success "hcloud CLI installed to /usr/local/bin/hcloud"
    else
        print_error "Unsupported OS: $OSTYPE"
        print_status "Please install hcloud CLI manually from:"
        echo "  https://github.com/hetznercloud/cli/releases/latest"
        exit 1
    fi
}

# Function to setup hcloud context
setup_hcloud_context() {
    print_status "Setting up Hetzner Cloud context..."

    # Check for existing contexts
    if hcloud context list >/dev/null 2>&1; then
        EXISTING_CONTEXTS=$(hcloud context list -o noheader | wc -l)
        if [ "$EXISTING_CONTEXTS" -gt 0 ]; then
            print_warning "Found $EXISTING_CONTEXTS existing context(s):"
            hcloud context list
            echo
            read -p "Do you want to create a new context? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Using existing context"
                # Test connection
                if hcloud server list >/dev/null 2>&1; then
                    print_success "Connection to Hetzner Cloud API successful!"
                    return 0
                else
                    print_error "Cannot connect with existing context"
                fi
            fi
        fi
    fi

    # Create new context
    echo
    print_status "Creating new hcloud context..."
    echo
    echo "To create a context, you need a Hetzner Cloud API token."
    echo "If you don't have one, follow these steps:"
    echo
    echo "1. Go to https://console.hetzner.cloud"
    echo "2. Select your project"
    echo "3. Go to Security → API Tokens"
    echo "4. Click 'Generate API Token'"
    echo "5. Choose 'Read & Write' permissions"
    echo "6. Copy the token"
    echo

    read -p "Enter a name for this context (default: netbird): " CONTEXT_NAME
    CONTEXT_NAME=${CONTEXT_NAME:-netbird}

    print_status "Creating context '$CONTEXT_NAME'..."
    if hcloud context create "$CONTEXT_NAME"; then
        print_success "Context '$CONTEXT_NAME' created successfully!"
    else
        print_error "Failed to create context"
        exit 1
    fi

    # Test the connection
    print_status "Testing connection to Hetzner Cloud API..."
    if hcloud server list >/dev/null 2>&1; then
        print_success "Connection successful!"

        # Show account info
        echo
        print_status "Account information:"
        echo "==================="

        # Get project info if possible
        PROJECT_INFO=$(hcloud server list -o json 2>/dev/null | head -1)
        if [ -n "$PROJECT_INFO" ]; then
            echo "✅ API connection working"
            echo "🔧 Context: $CONTEXT_NAME"

            # Show available resources
            SERVER_COUNT=$(hcloud server list -o noheader | wc -l)
            echo "🖥️  Servers: $SERVER_COUNT"

            LOCATION_COUNT=$(hcloud location list -o noheader | wc -l)
            echo "🌍 Available locations: $LOCATION_COUNT"

            echo "==================="
        fi
    else
        print_error "Connection failed! Please check your API token"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check hcloud CLI
    if ! command_exists hcloud; then
        print_warning "hcloud CLI is not installed"
        read -p "Would you like to install it automatically? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_error "hcloud CLI is required for deployment"
            echo "Please install manually from: https://github.com/hetznercloud/cli/releases/latest"
            exit 1
        fi
        install_hcloud_cli
    else
        print_success "hcloud CLI is installed"
        HCLOUD_VERSION=$(hcloud version | head -n1)
        print_status "Using $HCLOUD_VERSION"
    fi

    # Check if we can connect to Hetzner Cloud API
    if ! hcloud server list >/dev/null 2>&1; then
        print_warning "Cannot connect to Hetzner Cloud API"
        setup_hcloud_context
    else
        print_success "Hetzner Cloud API connection verified"
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

# Function to collect IP configuration
collect_ip_config() {
    print_header "=== IP Address Configuration ==="
    echo

    # Check if there are any Primary IPs available
    if ! hcloud primary-ip list >/dev/null 2>&1; then
        print_status "No Primary IPs found. The server will use an automatic IP address."
        return 0
    fi

    local ip_count=$(hcloud primary-ip list -o json | jq '. | length')

    if [ "$ip_count" -eq 0 ]; then
        print_status "No Primary IPs found. The server will use an automatic IP address."
        return 0
    fi

    print_status "Found $ip_count available Primary IP(s):"
    echo
    hcloud primary-ip list
    echo

    read -p "Would you like to use an existing Primary IP? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo
        print_status "Available Primary IPs:"
        hcloud primary-ip list --output columns=name,ip,type
        echo

        while true; do
            read -p "Enter Primary IP name or IP address (leave empty for automatic): " CUSTOM_IP

            if [ -z "$CUSTOM_IP" ]; then
                print_status "Using automatic IP assignment"
                break
            fi

            # Validate the IP exists
            if hcloud primary-ip describe "$CUSTOM_IP" >/dev/null 2>&1; then
                ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
                print_success "Selected Primary IP: $CUSTOM_IP ($ACTUAL_IP)"

                # Check if it's assigned
                IP_ASSIGNEE=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.assignee_id')
                if [ "$IP_ASSIGNEE" != "null" ] && [ -n "$IP_ASSIGNEE" ]; then
                    ASSIGNEE_NAME=$(hcloud server describe "$IP_ASSIGNEE" -o json 2>/dev/null | jq -r '.name' || echo "Unknown")
                    print_warning "This IP is currently assigned to server: $ASSIGNEE_NAME"
                    read -p "Continue anyway? The IP will be reassigned (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        continue
                    fi
                fi
                break
            else
                print_error "Primary IP '$CUSTOM_IP' not found. Please try again."
                print_status "Available options:"
                hcloud primary-ip list --output columns=name,ip
                echo
            fi
        done
    else
        print_status "Using automatic IP assignment"
    fi

    echo
}

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
    echo "ℹ️  Note: This SPA setup means NO CLIENT SECRET is needed - NetBird will use PKCE flow"
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
    echo "3. Check these default Redirect URIs (should be pre-selected):"
    echo "   ✅ https://login.microsoftonline.com/common/oauth2/nativeclient"
    echo "   ✅ https://login.live.com/oauth20_desktop.srf (LiveSDK)"
    echo "   ✅ msalbe064fd7-190f-4554-8c88-1124b8dabc31://auth (MSAL only)"
    echo "4. Add this additional URI for localhost fallback:"
    echo "   • http://localhost:53000"
    echo "5. Click 'Configure'"
    echo
    print_highlight "📋 Step 5: Set Application ID URI (REQUIRED)"
    echo "⚠️  CRITICAL: This must be done before API permissions!"
    echo "1. Go to 'Expose an API' section in your Azure AD app"
    echo "2. Click 'Set' next to Application ID URI"
    echo "3. Accept the default: api://[your-client-id]"
    echo "4. Click 'Save'"
    echo
    print_highlight "📋 Step 6: Configure Advanced Settings"
    echo "⚠️  REQUIRED: Enable public client flows for all platforms"
    echo "1. Go back to Authentication section, scroll to 'Advanced settings'"
    echo "2. Set 'Allow public client flows' to 'Yes'"
    echo "3. Set 'Treat application as a public client' to 'Yes'"
    echo "4. Click 'Save'"
    echo
    print_highlight "📋 Step 7: API Permissions"
    echo "In API permissions section, add these permissions:"
    echo "• Microsoft Graph > User.Read (delegated) - usually already present"
    echo "• Microsoft Graph > User.Read.All (delegated) - REQUIRED"
    echo "• Microsoft Graph > offline_access (delegated)"
    echo "• Click 'Grant admin consent for [organization]' - MANDATORY"
    echo "• Verify all permissions show 'Granted for [organization]'"
    echo
    print_highlight "📋 Step 8: DO NOT CREATE CLIENT SECRET"
    echo "⚠️  IMPORTANT: For universal public client authentication, do NOT create a client secret!"
    echo "• All NetBird clients use PKCE (Proof Key for Code Exchange)"
    echo "• Client secrets are not needed and cause authentication conflicts"
    echo "• If you already created one, that's okay - we'll configure it to not use it"
    echo
    print_highlight "📋 Step 9: Add API Scope (Fix for AADSTS65005)"
    echo "⚠️  IMPORTANT: Add scope to the Application ID URI you created in Step 5!"
    echo "1. Still in 'Expose an API' section"
    echo "2. Click 'Add a scope'"
    echo "3. Scope name: api"
    echo "4. Who can consent: Admins only"
    echo "5. Admin consent display name: Access NetBird API"
    echo "6. Admin consent description: Allows access to NetBird API"
    echo "7. State: Enabled"
    echo "8. Click 'Add scope'"
    echo
    print_highlight "📋 Step 10: Grant Admin Consent (Fix for AADSTS500011)"
    echo "⚠️  CRITICAL: Admin consent is required!"
    echo "1. Go back to 'API permissions'"
    echo "2. Click 'Grant admin consent for [your organization]'"
    echo "3. Confirm by clicking 'Yes'"
    echo "4. Ensure all permissions show 'Granted for [organization]'"
    echo
    print_highlight "📋 Step 11: Create Management App for User Enrichment (OPTIONAL)"
    echo "⚠️  OPTIONAL: For better user display (names instead of GUIDs), create a second app:"
    echo "1. Go to Azure AD > App Registrations > + New registration"
    echo "2. Name: 'NetBird Management' (separate from your SPA app)"
    echo "3. Supported account types: Single tenant"
    echo "4. No redirect URIs needed"
    echo "5. Click 'Register'"
    echo "6. Go to Certificates & secrets > + New client secret"
    echo "7. Description: 'NetBird Management Secret', Expires: 24 months"
    echo "8. Copy the secret VALUE immediately (you won't see it again)"
    echo "9. Go to API permissions > + Add permission > Microsoft Graph > Application permissions"
    echo "10. Add: User.Read.All (required), Directory.Read.All (recommended)"
    echo "11. Click 'Grant admin consent for [organization]' and confirm"
    echo "12. Copy: Application (client) ID and Object ID from Overview page"
    echo
    print_highlight "📋 Step 12: Collect Required Information"
    echo "From your SPA app Overview page, copy these values:"
    echo "• Application (client) ID"
    echo "• Directory (tenant) ID"
    echo "• Object ID"
    echo "• NO CLIENT SECRET NEEDED for SPA configuration"
    echo
    echo "From your Management app (if created), copy these values:"
    echo "• Management App Client ID"
    echo "• Management App Client Secret"
    echo "• Management App Object ID"
    echo
    print_highlight "📋 Step 13: Final Verification Checklist"
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
    echo "💻 Desktop Apps: Default Microsoft URIs + http://localhost:53000"
    echo "📱 Mobile Apps: Default Microsoft URIs + http://localhost:53000"
    echo "🔧 CLI Tools: Native client flows via default URIs"
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

    # Collect IP configuration
    collect_ip_config

    # Show detailed setup instructions
    show_azure_setup_instructions

    print_header "=== Azure AD Information Collection ==="
    echo
    echo "Enter the information you collected from your Azure AD application:"
    echo

    # Ask about SPA configuration (no client secret needed)
    print_warning "⚠️  IMPORTANT: For universal public client configuration, no client secret is needed"
    echo "This deployment uses PKCE (Proof Key for Code Exchange) for enhanced security."
    echo "This means:"
    echo "• No client secret is required or used"
    echo "• Server-side user management is disabled (users authenticate directly via web dashboard)"
    echo "• All authentication happens client-side using secure PKCE flow"
    echo
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
    print_header "=== Management App Configuration (Optional) ==="
    echo "For enhanced user display (names instead of GUIDs), you can configure a management app."
    echo "If you created a separate Management app as instructed above, enter its details:"
    echo
    read -p "Did you create a Management app for user enrichment? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Management App Client ID: " MGMT_CLIENT_ID
        while [[ ! "$MGMT_CLIENT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; do
            print_error "Please enter a valid management client ID (UUID format)"
            read -p "Management App Client ID: " MGMT_CLIENT_ID
        done

        read -p "Management App Client Secret: " MGMT_CLIENT_SECRET
        while [[ -z "$MGMT_CLIENT_SECRET" ]]; do
            print_error "Management client secret cannot be empty"
            read -p "Management App Client Secret: " MGMT_CLIENT_SECRET
        done

        read -p "Management App Object ID: " MGMT_OBJECT_ID
        while [[ ! "$MGMT_OBJECT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; do
            print_error "Please enter a valid management object ID (UUID format)"
            read -p "Management App Object ID: " MGMT_OBJECT_ID
        done

        print_success "Management app configuration will be enabled for user enrichment"
    else
        print_status "Skipping management app - users will display as GUIDs until configured later"
        MGMT_CLIENT_ID=""
        MGMT_CLIENT_SECRET=""
        MGMT_OBJECT_ID=""
    fi

    echo
    print_header "=== Configuration Summary ==="
    echo "Customer: $CUSTOMER_NAME"
    echo "Server Name: $SERVER_NAME"
    echo "Domain: $NETBIRD_DOMAIN"
    echo "Tenant ID: $AZURE_TENANT_ID"
    echo "Client ID: $AZURE_CLIENT_ID"
    echo "Object ID: $AZURE_OBJECT_ID"
    echo "Authentication: Universal Public Client with PKCE (no client secret)"
    if [[ -n "$MGMT_CLIENT_ID" ]]; then
        echo "Management App: Enabled for user enrichment"
        echo "Management Client ID: $MGMT_CLIENT_ID"
        echo "Management Object ID: $MGMT_OBJECT_ID"
    else
        echo "Management App: Not configured (users will show as GUIDs)"
    fi
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
    if [ -n "$CUSTOM_IP" ]; then
        ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
        echo "  - IPv4: Custom Primary IP ($ACTUAL_IP)"
        echo "  - Primary IP Name: $CUSTOM_IP"
    else
        echo "  - IPv4: Automatic assignment"
    fi
    echo "  - Purpose: NetBird Self-Hosted"
    echo "  - Firewall: $FIREWALL_NAME"
    echo

    # Ensure SSH key exists
    ensure_ssh_key

    # Create firewall with NetBird ports
    create_firewall

    # Handle custom IP if specified
    PRIMARY_IP_PARAM=""
    if [ -n "$CUSTOM_IP" ]; then
        print_status "Checking Primary IP '$CUSTOM_IP'..."

        # Check if specified IP exists as a Primary IP (by name or IP address)
        if ! hcloud primary-ip describe "$CUSTOM_IP" >/dev/null 2>&1; then
            print_error "Primary IP '$CUSTOM_IP' not found!"
            print_status "Available Primary IPs:"
            hcloud primary-ip list
            echo
            print_status "To create a new Primary IP:"
            echo "  hcloud primary-ip create --type ipv4 --location $LOCATION --name my-ip --assignee-type server"
            echo
            print_status "Examples:"
            echo "  $0 --ip my-static-ip                 # Use by name"
            echo "  $0 --ip 192.168.1.100               # Use by IP address"
            exit 1
        fi

        # Check if the IP is already assigned
        IP_ASSIGNEE=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.assignee_id')
        if [ "$IP_ASSIGNEE" != "null" ] && [ -n "$IP_ASSIGNEE" ]; then
            ASSIGNEE_NAME=$(hcloud server describe "$IP_ASSIGNEE" -o json 2>/dev/null | jq -r '.name' || echo "Unknown")
            ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
            print_warning "Primary IP '$CUSTOM_IP' ($ACTUAL_IP) is already assigned to server: $ASSIGNEE_NAME (ID: $IP_ASSIGNEE)"
            read -p "Continue anyway? The IP will be reassigned to the new server (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Deployment cancelled"
                exit 0
            fi
        fi

        ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
        print_success "Primary IP '$CUSTOM_IP' ($ACTUAL_IP) is available for assignment"
        PRIMARY_IP_PARAM="--primary-ipv4 $CUSTOM_IP"
    fi

    # Create server with firewall
    print_status "Creating server with hcloud..."
    if [ -n "$CUSTOM_IP" ]; then
        print_status "Using Primary IP: $CUSTOM_IP ($ACTUAL_IP)"
        hcloud server create \
            --name "$SERVER_NAME" \
            --type "$SERVER_TYPE" \
            --image "$IMAGE" \
            --location "$LOCATION" \
            --ssh-key "$SSH_KEY_NAME" \
            --firewall "$FIREWALL_NAME" \
            --primary-ipv4 "$CUSTOM_IP" \
            --label "managed-by=netbird-selfhosted" \
            --label "purpose=netbird-server" \
            --label "customer=${CUSTOMER_NAME_CLEAN:-default}" \
            --label "created=$(date +%Y-%m-%d)"
    else
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
    fi

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

    print_status "Waiting for server to fully boot and SSH to be available..."

    # Initial delay with countdown - server needs time to boot
    print_status "Waiting 30 seconds for server initialization..."
    for i in {30..1}; do
        printf "\rServer boot countdown: %2d seconds remaining..." $i
        sleep 1
    done
    echo
    print_success "Initial wait complete, testing SSH connection..."

    print_status "Testing SSH connection on $server_ip (timeout: 5 minutes)..."
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
            local ssh_output=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -o PasswordAuthentication=no -o LogLevel=ERROR root@$server_ip "echo 'SSH_TEST_SUCCESS'" 2>&1 &)
            local ssh_pid=$!
            local ssh_exit_code=124

            # Manual timeout implementation
            (sleep 30 && kill $ssh_pid 2>/dev/null) &
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

                # Create SSH alias now that SSH is working
                create_ssh_alias "$server_ip" "$CUSTOMER_NAME"

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

# Function to create SSH alias after SSH is confirmed working
create_ssh_alias() {
    local server_ip="$1"
    local company_name="$2"

    print_status "Creating SSH alias for easy access..."

    # Create a short, practical alias from company name
    local short_alias=$(echo "$company_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-10)

    # Ensure SSH config file exists
    touch ~/.ssh/config

    # Remove any existing entries for this IP or alias
    ssh-keygen -R $server_ip >/dev/null 2>&1 || true
    sed -i.bak "/^Host $short_alias$/,/^$/d" ~/.ssh/config 2>/dev/null || true

    # Add SSH config entry
    cat >> ~/.ssh/config << EOF

# NetBird server for $company_name
Host $short_alias
    HostName $server_ip
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile ~/.ssh/known_hosts

EOF

    print_success "SSH alias '$short_alias' created"
    print_highlight "You can now connect with: ssh $short_alias"

    # Create local alias file for easy reference
    local alias_file="$HOME/.netbird_servers"
    touch "$alias_file"

    # Remove any existing entry for this company/IP
    grep -v "$company_name|" "$alias_file" > "$alias_file.tmp" 2>/dev/null || true
    mv "$alias_file.tmp" "$alias_file" 2>/dev/null || true

    # Add new entry
    echo "$company_name|$short_alias|$server_ip|$(date)" >> "$alias_file"
    print_success "Server alias saved to $alias_file"
}

# Function to manually add server to known hosts (legacy)
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
# Function to install NetBird on the server
install_netbird() {
    local server_ip=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')

    print_header "=== Installing NetBird on Server ==="
    echo

    print_status "Verifying SSH connection for installation..."

    # Use the same SSH parameters that worked before
    local ssh_test_result
    local ssh_exit_code

    # Simple SSH test - just verify basic connectivity since SSH was already confirmed working
    print_status "Quick SSH connectivity check..."

    # Use a simple test that's more likely to succeed
    if timeout 30 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes root@$server_ip "echo 'ready'" >/dev/null 2>&1; then
        print_success "SSH connection verified - proceeding with installation"
    else
        print_status "SSH quick test didn't respond, but this is often normal"
        print_status "SSH was confirmed working moments ago during server setup"
        print_status "Proceeding with installation (SSH usually works fine for actual commands)"
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
apt update
apt install -y curl wget git jq

# Install Docker using official method for better compatibility
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh

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

# Verify clone succeeded and directory exists
if [ ! -d "netbird" ]; then
    echo "ERROR: Git clone failed - netbird directory not found"
    echo "Directory contents:"
    ls -la
    exit 1
fi

cd netbird/infrastructure_files/

# Verify we're in the right place
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la

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

    # Wait a moment for filesystem to settle
    sleep 2

    # Verify installation completed successfully with detailed debugging
    print_status "Verifying installation..."

    # Show what was created
    print_status "Checking directory structure..."
    ssh -o StrictHostKeyChecking=no root@$server_ip "echo '=== /opt directory ===' && ls -la /opt/ && echo '=== /opt/netbird ===' && ls -la /opt/netbird/ 2>&1 || echo '/opt/netbird not found' && echo '=== /opt/netbird/netbird ===' && ls -la /opt/netbird/netbird/ 2>&1 || echo '/opt/netbird/netbird not found'"

    if ! ssh -o StrictHostKeyChecking=no root@$server_ip "test -d /opt/netbird/netbird/infrastructure_files && test -f /opt/netbird/netbird/infrastructure_files/configure.sh"; then
        print_error "Installation verification failed - required directories/files not found"
        print_status "Full diagnostic output shown above"
        print_status "You can manually check with: ssh root@$server_ip 'find /opt -name infrastructure_files'"
        return 1
    fi

    print_success "NetBird installation files prepared and verified"
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

# Debug: Check what exists
echo "=== Debugging Directory Structure ==="
echo "Contents of /opt/netbird:"
ls -la /opt/netbird/ || echo "Directory /opt/netbird does not exist"
echo
echo "Looking for netbird subdirectory:"
ls -la /opt/netbird/netbird/ || echo "Directory /opt/netbird/netbird does not exist"
echo
echo "Looking for infrastructure_files:"
ls -la /opt/netbird/netbird/infrastructure_files/ || echo "Directory /opt/netbird/netbird/infrastructure_files does not exist"
echo "=== End Debug ==="
echo

# Try to cd into the directory
if [ ! -d "/opt/netbird/netbird/infrastructure_files" ]; then
    echo "ERROR: Directory /opt/netbird/netbird/infrastructure_files does not exist!"
    echo "Installation may have failed. Please check the installation logs."
    exit 1
fi

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
#
# Server-side user enrichment via Azure Graph API
# If enabled, NetBird will fetch user names/emails from Azure AD
# instead of displaying user GUIDs in the dashboard
EOF

# Add management app configuration based on user input
if [[ -n "$MGMT_CLIENT_ID" ]]; then
cat >> setup.env << 'MGMT_CONFIG_EOF'
NETBIRD_MGMT_IDP="azure"
NETBIRD_IDP_MGMT_CLIENT_ID="$MGMT_CLIENT_ID"
NETBIRD_IDP_MGMT_CLIENT_SECRET="$MGMT_CLIENT_SECRET"
NETBIRD_IDP_MGMT_EXTRA_OBJECT_ID="$MGMT_OBJECT_ID"
NETBIRD_IDP_MGMT_EXTRA_GRAPH_API_ENDPOINT="https://graph.microsoft.com/v1.0"
MGMT_CONFIG_EOF
else
cat >> setup.env << 'NO_MGMT_CONFIG_EOF'
NETBIRD_MGMT_IDP=""
NETBIRD_IDP_MGMT_CLIENT_ID=""
NETBIRD_IDP_MGMT_CLIENT_SECRET=""
NETBIRD_IDP_MGMT_EXTRA_OBJECT_ID=""
NETBIRD_IDP_MGMT_EXTRA_GRAPH_API_ENDPOINT=""
NO_MGMT_CONFIG_EOF
fi

cat >> setup.env << 'FINAL_CONFIG_EOF'

# Optional: Single account mode (recommended for most deployments)
# This ensures all users join the same NetBird account/network
NETBIRD_MGMT_SINGLE_ACCOUNT_MODE=true
FINAL_CONFIG_EOF

echo "Configuration file created successfully"

# Run the configuration script
echo "Running NetBird configuration script..."
cd /opt/netbird/netbird/infrastructure_files
chmod +x configure.sh
./configure.sh setup.env

echo "NetBird configured successfully!"
echo "Configuration files generated in: /opt/netbird/netbird/infrastructure_files/artifacts/"

# Apply OAuth SPA fixes and nginx configuration
echo "Applying OAuth SPA and nginx fixes..."

cd /opt/netbird/netbird/infrastructure_files/artifacts/

# Fix 1: Enable IDP signing key refresh to prevent token validation issues
echo "Enabling IDP signing key refresh for Azure AD..."
if [ -f management.json ]; then
    # Check if jq is available
    if command -v jq >/dev/null 2>&1; then
        # Use jq to safely update the JSON
        jq '.HttpConfig.IdpSignKeyRefreshEnabled = true' management.json > management.json.tmp && mv management.json.tmp management.json
        echo "✓ IDP signing key refresh enabled in management.json"
    else
        # Fallback: use sed (less safe but works if jq isn't available)
        sed -i 's|"IdpSignKeyRefreshEnabled": false|"IdpSignKeyRefreshEnabled": true|g' management.json
        echo "✓ IDP signing key refresh enabled in management.json (via sed)"
    fi
else
    echo "⚠ Warning: management.json not found, skipping IDP key refresh configuration"
fi

# Fix 2: Update docker-compose.yml for SPA authentication (no client secret)
echo "Updating OAuth configuration for SPA authentication..."
sed -i 's|AUTH_CLIENT_SECRET=.*|AUTH_CLIENT_SECRET=|g' docker-compose.yml

# Fix 3: Apply nginx SPA routing fix
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

    # Copy the configuration script to the server for better debugging
    if ! scp -o StrictHostKeyChecking=no /tmp/netbird-configure.sh root@$server_ip:/tmp/netbird-configure.sh 2>/dev/null; then
        print_error "Failed to copy configuration script to server"
        return 1
    fi

    # Execute with better error handling
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 root@$server_ip "chmod +x /tmp/netbird-configure.sh && /tmp/netbird-configure.sh"; then
        print_error "NetBird configuration failed"
        print_status "The configuration script has been saved to /tmp/netbird-configure.sh on the server"
        print_status "You can manually SSH and run: /tmp/netbird-configure.sh"
        print_status "Or check what went wrong with: ssh root@$server_ip 'cat /tmp/netbird-configure.sh'"
        return 1
    fi

    # Verify configuration produced the expected files
    print_status "Verifying configuration..."
    if ! ssh -o StrictHostKeyChecking=no root@$server_ip "test -f /opt/netbird/netbird/infrastructure_files/artifacts/docker-compose.yml"; then
        print_error "Configuration verification failed - docker-compose.yml not found"
        print_status "Configuration may have partially completed. Check /opt/netbird/netbird/infrastructure_files/artifacts/"
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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

cd /opt/netbird/netbird/infrastructure_files/artifacts/

# Detect Docker Compose command - try multiple methods
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker >/dev/null 2>&1; then
    # Try docker compose without checking version first
    DOCKER_COMPOSE_CMD="docker compose"
    echo "Using 'docker compose' (assuming Docker Compose v2)"
else
    echo "ERROR: Docker not found! Installing Docker..."
    # Docker should have been installed in the setup, but try anyway
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    DOCKER_COMPOSE_CMD="docker compose"
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


EOF

    # Always ensure enhanced management script is uploaded BEFORE starting services
    print_status "Uploading enhanced management script..."

    # Try to upload the enhanced script using multiple methods
    enhanced_script_uploaded=false

    # Method 1: Try SCP first
    if [ -f "$SCRIPT_DIR/netbird-management-enhanced.sh" ]; then
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$SCRIPT_DIR/netbird-management-enhanced.sh" root@$server_ip:/root/netbird-management.sh 2>/dev/null; then
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "chmod +x /root/netbird-management.sh"
            print_success "Enhanced management script uploaded via SCP"
            enhanced_script_uploaded=true
        else
            print_status "SCP upload failed, trying SSH method..."
            # Method 2: Upload via SSH pipe
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "cat > /root/netbird-management.sh" < "$SCRIPT_DIR/netbird-management-enhanced.sh" && ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "chmod +x /root/netbird-management.sh"; then
                print_success "Enhanced management script uploaded via SSH"
                enhanced_script_uploaded=true
            else
                print_warning "SSH upload also failed, will use embedded version"
            fi
        fi
    fi

    # If enhanced script wasn't uploaded, use embedded version
    if [ "$enhanced_script_uploaded" = false ]; then
        print_status "Using embedded enhanced management script as fallback"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "cat > /root/netbird-management.sh" << 'ENHANCED_MGMT_EOF'
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

print_header() {
    echo -e "${PURPLE}=== $1 ===${NC}"
}

# SSL Certificate check function
check_ssl_certificate() {
    local domain="$1"
    local port="${2:-443}"

    print_status "Checking SSL certificate for $domain:$port..."

    # Check if certificate is valid
    if echo | openssl s_client -connect "$domain:$port" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null; then
        print_success "SSL certificate is valid for $domain"

        # Show certificate details
        echo | openssl s_client -connect "$domain:$port" -servername "$domain" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null
        return 0
    else
        print_error "SSL certificate check failed for $domain"
        return 1
    fi
}

# Detect Docker Compose command
detect_docker_compose() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo "docker compose"  # Default fallback
    fi
}

DOCKER_COMPOSE_CMD=$(detect_docker_compose)

# Function to get service URLs from environment
get_service_urls() {
    if [ -f "$NETBIRD_CONFIG" ]; then
        NETBIRD_DOMAIN=$(grep "NETBIRD_DOMAIN=" "$NETBIRD_CONFIG" | cut -d'=' -f2)
        NETBIRD_MGMT_API_ENDPOINT=$(grep "NETBIRD_MGMT_API_ENDPOINT=" "$NETBIRD_CONFIG" | cut -d'=' -f2)
        NETBIRD_MGMT_GRPC_API_ENDPOINT=$(grep "NETBIRD_MGMT_GRPC_API_ENDPOINT=" "$NETBIRD_CONFIG" | cut -d'=' -f2)
    fi
}

# Main command handling
case "${1:-}" in
    "status")
        cd "$COMPOSE_DIR" || exit 1
        print_header "NetBird Service Status"
        $DOCKER_COMPOSE_CMD ps
        ;;
    "health")
        cd "$COMPOSE_DIR" || exit 1
        print_header "NetBird Health Check"

        # Get service URLs
        get_service_urls

        # Check container status
        print_status "Checking container status..."
        $DOCKER_COMPOSE_CMD ps

        # Check if services are responding
        if [ -n "$NETBIRD_DOMAIN" ]; then
            print_status "Checking SSL certificates..."
            check_ssl_certificate "$NETBIRD_DOMAIN" 443
            check_ssl_certificate "$NETBIRD_DOMAIN" 33073
        fi

        # Check logs for errors
        print_status "Recent error logs:"
        $DOCKER_COMPOSE_CMD logs --tail=10 | grep -i error || echo "No recent errors found"
        ;;
    "logs")
        cd "$COMPOSE_DIR" || exit 1
        if [ -n "$2" ]; then
            print_header "Logs for service: $2"
            $DOCKER_COMPOSE_CMD logs -f "$2"
        else
            print_header "All NetBird Service Logs"
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
        $DOCKER_COMPOSE_CMD down
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
    *)
        echo "Enhanced NetBird Management Script v2.1.0"
        echo "Usage: $0 {status|health|logs|restart|stop|start|update}"
        echo ""
        echo "Commands:"
        echo "  status      - Show service status"
        echo "  health      - Complete health check"
        echo "  logs        - Show service logs"
        echo "  restart     - Restart all services"
        echo "  stop        - Stop all services"
        echo "  start       - Start all services"
        echo "  update      - Update and restart services"
        echo ""
        echo "Using: $DOCKER_COMPOSE_CMD"
        ;;
esac
ENHANCED_MGMT_EOF

        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@$server_ip "chmod +x /root/netbird-management.sh"
        print_success "Enhanced management script embedded successfully"
    fi

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
    if [ -n "$CUSTOM_IP" ]; then
        ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
        echo "Primary IP: $CUSTOM_IP ($ACTUAL_IP - custom assignment)"
    fi
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
    if [[ -n "$MGMT_CLIENT_ID" ]]; then
        echo "  User Enrichment: Enabled via Management App"
        echo "  Management Client ID: $MGMT_CLIENT_ID"
    else
        echo "  User Enrichment: Disabled (users display as GUIDs)"
        echo "  Note: To enable later, configure management app and update setup.env"
    fi
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
    if [ -n "$CUSTOM_IP" ]; then
        ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
        echo "   • Primary IP: $CUSTOM_IP ($ACTUAL_IP)"
        echo
        echo "   ✅ Using Primary IP: Benefits include:"
        echo "   • IP persists if server is recreated"
        echo "   • Stable DNS records (no IP changes)"
        echo "   • Can be transferred between servers"
        echo "   • Same cost as regular IP (€0.50/month)"
    fi
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
    # Show SSH alias information if available
    local short_alias=$(echo "$CUSTOMER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-10)

    if grep -q "Host $short_alias" ~/.ssh/config 2>/dev/null; then
        print_highlight "8. Easy SSH Access (Short Alias):"
        echo "   ssh $short_alias"
        echo "   # This connects to: $server_ip"
        echo "   # Alias saved for: $CUSTOMER_NAME"
        echo
        print_highlight "9. Management Commands with Alias:"
        echo "   ssh $short_alias '/root/netbird-management.sh status'"
        echo "   ssh $short_alias '/root/netbird-management.sh health'"
        echo "   ssh $short_alias '/root/netbird-management.sh logs'"
    fi
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🛠️  Useful Management Commands"
    echo "═══════════════════════════════════════════════════════════════"
    echo "# Check all services status"
    echo "ssh root@$server_ip '/root/netbird-management.sh status'"

    # Show alias commands if available
    local short_alias=$(echo "$CUSTOMER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-10)

    if grep -q "Host $short_alias" ~/.ssh/config 2>/dev/null; then
        echo "# OR using short alias:"
        echo "ssh $short_alias '/root/netbird-management.sh status'"
    fi
    echo
    echo "# Complete health check (services, SSL, Azure AD)"
    echo "ssh root@$server_ip '/root/netbird-management.sh health'"

    if grep -q "Host $short_alias" ~/.ssh/config 2>/dev/null; then
        echo "# OR: ssh $short_alias '/root/netbird-management.sh health'"
    fi
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

    # Add Primary IP management commands if custom IP was used
    if [ -n "$CUSTOM_IP" ]; then
        echo "# Primary IP management"
        echo "hcloud primary-ip list"
        echo "hcloud primary-ip describe $CUSTOM_IP"
        echo "hcloud primary-ip unassign $CUSTOM_IP  # Unassign from server"
        echo "hcloud primary-ip assign $CUSTOM_IP --assignee $SERVER_NAME  # Reassign to server"
        echo
    fi
    echo "═══════════════════════════════════════════════════════════════"
    echo "  💰 Cost Information & Server Management"
    echo "═══════════════════════════════════════════════════════════════"
    if [ -n "$CUSTOM_IP" ]; then
        echo "Monthly Cost: ~€3.79 (€3.29 CAX11 server + €0.50 Primary IPv4)"
        echo "Note: Primary IP persists after server deletion (€0.50/month until deleted)"
    else
        echo "Monthly Cost: ~€3.79 (€3.29 CAX11 server + €0.50 IPv4)"
    fi
    echo "Daily Cost: ~€0.13"
    echo
    echo "Cost Management:"
    echo "To stop server (saves costs): hcloud server poweroff $SERVER_NAME"
    echo "To restart server: hcloud server poweron $SERVER_NAME"
    echo "To delete server: hcloud server delete $SERVER_NAME"
    if [ -n "$CUSTOM_IP" ]; then
        ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
        echo "To delete Primary IP: hcloud primary-ip delete $CUSTOM_IP  # $ACTUAL_IP"
        echo "Note: Primary IP will remain assigned until server deletion"
    fi
    echo "To delete firewall: hcloud firewall delete $FIREWALL_NAME"
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
    echo "5. Users show as GUIDs instead of names:"
    echo "   • Management app not configured or misconfigured"
    echo "   • Check Graph API permissions: User.Read.All required"
    echo "   • Verify management app has admin consent granted"
    echo "   • Ensure users have displayName, mail fields in Azure AD"
    echo "   • Delete GUID user in dashboard, log out/in to refresh"
    echo "   • Check logs: ssh root@$server_ip '/root/netbird-management.sh logs | grep -i graph'"
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
        # Get firewall resources with better JSON parsing
        local firewall_data=$(hcloud firewall describe "$FIREWALL_NAME" -o json 2>/dev/null)
        local firewall_resources=$(echo "$firewall_data" | jq -r '.resources[]? | select(.type=="server") | .server.name' 2>/dev/null)
        local rule_count=$(echo "$firewall_data" | jq '.rules | length' 2>/dev/null || echo "0")

        if echo "$firewall_resources" | grep -q "$SERVER_NAME"; then
            print_success "Firewall '$FIREWALL_NAME' is properly applied to server '$SERVER_NAME'"
            print_status "Firewall has $rule_count security rules configured"
        else
            print_warning "Firewall '$FIREWALL_NAME' exists but may not be applied to server '$SERVER_NAME'"
            print_status "Applied to servers: $(echo "$firewall_resources" | tr '\n' ' ' | sed 's/ $//')"
            print_status "Expected server: $SERVER_NAME"

            # Try to auto-apply the firewall
            print_status "Attempting to apply firewall to server..."
            if hcloud firewall apply-to-resource "$FIREWALL_NAME" --type server --resource "$SERVER_NAME" 2>/dev/null; then
                print_success "Firewall successfully applied to server"
            else
                print_warning "Could not auto-apply firewall - manual intervention may be needed"
            fi
        fi
    else
        print_error "Firewall '$FIREWALL_NAME' not found"
        print_status "Available firewalls: $(hcloud firewall list -o noheader | cut -d' ' -f1 | tr '\n' ' ')"
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

    # Optional SSL certificate verification
    echo
    print_status "SSL Certificate verification can take 5-15 minutes after DNS configuration..."
    read -p "Would you like to verify SSL certificate now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        verify_ssl_certificate "$NETBIRD_DOMAIN" "$server_ip"
    else
        print_status "Skipping SSL verification - you can check later with:"
        print_status "ssh root@$server_ip '/root/netbird-management.sh ssl'"
    fi

    echo
    print_status "Verification complete. Check the summary above for next steps."

    # Show Azure AD restart instructions if needed
    show_azure_restart_instructions "$server_ip"
}

# Function to list saved NetBird server aliases
list_server_aliases() {
    local alias_file="$HOME/.netbird_servers"

    if [ ! -f "$alias_file" ]; then
        print_status "No saved NetBird server aliases found."
        print_status "Deploy a server first to create aliases."
        return 0
    fi

    print_header "🖥️  Saved NetBird Server Aliases"
    echo

    echo "Format: Company | SSH Alias | IP Address | Created"
    echo "═══════════════════════════════════════════════════════"

    while IFS='|' read -r company alias ip created; do
        if [ -n "$company" ]; then
            printf "%-20s | %-10s | %-15s | %s\n" "$company" "$alias" "$ip" "$created"
        fi
    done < "$alias_file"

    echo
    print_highlight "🔗 Quick Connection Commands:"
    echo

    while IFS='|' read -r company alias ip created; do
        if [ -n "$company" ]; then
            echo "# Connect to $company NetBird server:"
            echo "ssh $alias"
            echo "ssh $alias '/root/netbird-management.sh status'"
            echo "ssh $alias '/root/netbird-management.sh health'"
            echo
        fi
    done < "$alias_file"

    print_status "SSH config entries are saved in ~/.ssh/config"
    print_status "Server list is saved in $alias_file"
    echo
    print_highlight "💡 Examples:"
    echo "ssh nb2                                    # Connect to server"
    echo "ssh nb2 '/root/netbird-management.sh ssl' # Check SSL status"
    echo "ssh nb2 '/root/netbird-management.sh logs'# View logs"
}

# Function to show usage
show_usage() {
    cat << EOF
NetBird Self-Hosted Deployment Script v2.3.0 (Enhanced with SPA OAuth & Token Refresh)

Usage: $0 [options]
       $0 list-servers
       $0 list-ips

Commands:
  list-servers           List all saved NetBird server aliases and connection info
  list-ips              List available Primary IPs in Hetzner Cloud

Options:
  --customer <name>      Customer name (for server naming)
  --domain <domain>      NetBird domain (e.g., netbird.yourdomain.com)
  --tenant-id <id>       Azure AD Tenant ID
  --client-id <id>       Azure AD Application (client) ID
  --client-secret <secret> Azure AD Client Secret (not needed for SPA config)
  --object-id <id>       Azure AD Object ID
  --mgmt-client-id <id>  Management App Client ID (for user enrichment)
  --mgmt-secret <secret> Management App Client Secret (for user enrichment)
  --mgmt-object-id <id>  Management App Object ID (for user enrichment)
  --email <email>        Let's Encrypt email
  --server-name <name>   Custom server name (default: netbird-selfhosted-<customer>)
  --server-type <type>   Server type (default: cax11)
  --location <loc>       Server location (default: nbg1)
  --ip <name_or_ip>     Use existing Primary IP (name or IP address)
  --list-ips            List available Primary IPs and exit
  --help, -h            Show this help message

Examples:
  # Interactive mode (recommended)
  $0

  # List saved server aliases
  $0 list-servers

  # List available Primary IPs
  $0 list-ips

  # List available Primary IPs (alternative syntax)
  $0 --list-ips

  # Use specific Primary IP by name
  $0 --customer "Acme Corp" --ip my-static-ip

  # Use specific Primary IP by IP address
  $0 --customer "Acme Corp" --ip 192.168.1.100

  # Non-interactive mode (SPA only)
  ./deploy-netbird-selfhosted.sh --customer "Acme Corp" \
     --domain netbird.company.com \
     --tenant-id "12345678-1234-1234-1234-123456789012" \
     --client-id "87654321-4321-4321-4321-210987654321" \
     --object-id "11111111-2222-3333-4444-555555555555" \
     --email admin@company.com

  # Non-interactive mode with user enrichment
  ./deploy-netbird-selfhosted.sh --customer "Acme Corp" \
     --domain netbird.company.com \
     --tenant-id "12345678-1234-1234-1234-123456789012" \
     --client-id "87654321-4321-4321-4321-210987654321" \
     --object-id "11111111-2222-3333-4444-555555555555" \
     --mgmt-client-id "22222222-3333-4444-5555-666666666666" \
     --mgmt-secret "management-app-secret-value" \
     --mgmt-object-id "33333333-4444-5555-6666-777777777777" \
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
            --mgmt-client-id)
                MGMT_CLIENT_ID="$2"
                shift 2
                ;;
            --mgmt-secret)
                MGMT_CLIENT_SECRET="$2"
                shift 2
                ;;
            --mgmt-object-id)
                MGMT_OBJECT_ID="$2"
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
            --ip)
                CUSTOM_IP="$2"
                shift 2
                ;;
            --list-ips)
                print_header "🌐 Available Primary IPs in Hetzner Cloud"
                echo
                hcloud primary-ip list
                echo
                print_status "To create a new Primary IP:"
                echo "  hcloud primary-ip create --type ipv4 --location $LOCATION --name my-ip --assignee-type server"
                echo
                print_status "To use an existing Primary IP:"
                echo "  $0 --ip <primary-ip-name-or-address>"
                echo
                print_status "Examples:"
                echo "  $0 --ip my-static-ip                 # Use by name"
                echo "  $0 --ip 192.168.1.100               # Use by IP address"
                exit 0
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
    # Handle special commands first
    if [ "$1" = "list-servers" ] || [ "$1" = "list" ]; then
        list_server_aliases
        exit 0
    fi

    if [ "$1" = "list-ips" ]; then
        print_header "🌐 Available Primary IPs in Hetzner Cloud"
        echo
        hcloud primary-ip list
        echo
        print_status "To create a new Primary IP:"
        echo "  hcloud primary-ip create --type ipv4 --location $LOCATION --name my-ip --assignee-type server"
        echo
        print_status "To use an existing Primary IP:"
        echo "  $0 --ip <primary-ip-name-or-address>"
        echo
        print_status "Examples:"
        echo "  $0 --ip my-static-ip                 # Use by name"
        echo "  $0 --ip 192.168.1.100               # Use by IP address"
        exit 0
    fi




    # Parse command line arguments
    parse_arguments "$@"

    # Show banner
    show_banner

    # Check prerequisites
    check_prerequisites

    # Collect Azure AD configuration if not provided via command line
    if [ -z "$NETBIRD_DOMAIN" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_OBJECT_ID" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
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

    # Validate configuration (note: client secret and management app not required for SPA)
    if [ -z "$NETBIRD_DOMAIN" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_OBJECT_ID" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
        print_error "Missing required configuration. Please provide all Azure AD details."
        exit 1
    fi

    print_header "=== Deployment Summary ==="
    echo "Customer: ${CUSTOMER_NAME:-N/A}"
    echo "Server: $SERVER_NAME ($SERVER_TYPE, $LOCATION)"
    echo "Domain: $NETBIRD_DOMAIN"
    if [ -n "$CUSTOM_IP" ]; then
        ACTUAL_IP=$(hcloud primary-ip describe "$CUSTOM_IP" -o json | jq -r '.ip')
        echo "IP Address: Custom Primary IP ($ACTUAL_IP)"
        echo "Primary IP Name: $CUSTOM_IP"
    else
        echo "IP Address: Automatic assignment"
    fi
    echo "Identity Provider: Azure AD (SPA with PKCE)"
    echo "Authentication: No client secret (PKCE-only)"
    if [[ -n "$MGMT_CLIENT_ID" ]]; then
        echo "User Enrichment: Enabled (Management App configured)"
    else
        echo "User Enrichment: Disabled (users will show as GUIDs)"
    fi
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
