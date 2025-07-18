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

print_highlight() {
    echo -e "${CYAN}$1${NC}"
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

    recent_logs=$($DOCKER_COMPOSE_CMD logs --tail=50 management 2>/dev/null | grep -i "403\|permission\|graph\|azure\|clientsecret" | tail -5)

    if echo "$recent_logs" | grep -q "ClientSecret is missing"; then
        print_status "Azure AD configured for SPA (Single Page Application) mode"
        print_success "This is correct - SPA applications don't use client secrets"
        print_status "Server-side user management is disabled (users authenticate via web dashboard)"
        return 0
    elif echo "$recent_logs" | grep -q "403\|AADSTS65005\|AADSTS500011"; then
        print_error "Azure AD authentication errors detected!"
        print_status "Recent authentication errors:"
        echo "$recent_logs"
        echo

        # Check for specific error types
        if echo "$recent_logs" | grep -q "AADSTS65005"; then
            print_error "AADSTS65005: API scope 'api' doesn't exist"
            print_status "Fix: Configure API scope in Azure AD (run: $0 azure-fix)"
        fi

        if echo "$recent_logs" | grep -q "AADSTS500011"; then
            print_error "AADSTS500011: Resource principal not found"
            print_status "Fix: Grant admin consent in Azure AD (run: $0 azure-fix)"
        fi

        if echo "$recent_logs" | grep -q "403"; then
            print_error "403: Insufficient permissions"
            print_status "Fix: Add Microsoft Graph permissions (run: $0 azure-fix)"
        fi

        print_warning "Run '$0 azure-fix' for detailed resolution steps"
        return 1
    elif echo "$recent_logs" | grep -q -i "azure\|graph"; then
        print_success "Azure AD integration appears to be working"
        if [ -n "$recent_logs" ]; then
            echo "Recent Azure AD activity:"
            echo "$recent_logs"
        fi
    else
        print_status "No recent Azure AD activity in logs"
        print_status "This is normal for SPA configurations (no server-side user management)"
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

# Function to show certificate generation logs
show_cert_logs() {
    print_status "SSL Certificate Generation Logs"
    echo "════════════════════════════════════════"

    cd "$COMPOSE_DIR" || return 1

    # Show certificate-related logs
    $DOCKER_COMPOSE_CMD logs 2>/dev/null | grep -i "certificate\|ssl\|acme\|letsencrypt" | tail -20

    echo
    print_status "To monitor certificate generation in real-time:"
    print_status "$0 logs | grep -i \"certificate\\|ssl\\|acme\""
}

# Function to test connectivity
test_connectivity() {
    local domain=$(get_netbird_domain)

    if [ "$domain" = "unknown" ]; then
        print_error "Cannot determine NetBird domain from configuration"
        return 1
    fi

    print_status "Testing connectivity to $domain"
    echo "════════════════════════════════════════"

    # Test DNS resolution
    print_status "DNS Resolution:"
    if dns_result=$(dig +short "$domain" 2>/dev/null); then
        if [ -n "$dns_result" ]; then
            print_success "DNS resolves to: $dns_result"
        else
            print_error "DNS resolution failed - no A record found"
        fi
    else
        print_error "DNS resolution failed - dig command failed"
    fi

    echo

    # Test HTTP connectivity
    print_status "HTTP Connectivity (port 80):"
    if timeout 5 curl -s -o /dev/null -w "%{http_code}" "http://$domain" | grep -q "200\|30[0-9]"; then
        print_success "HTTP connection successful"
    else
        print_error "HTTP connection failed"
    fi

    echo

    # Test HTTPS connectivity
    print_status "HTTPS Connectivity (port 443):"
    if timeout 10 curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "200\|30[0-9]"; then
        print_success "HTTPS connection successful"
    else
        print_error "HTTPS connection failed"
    fi

    echo

    # Check SSL certificate
    check_ssl_certificate
}

# Function to backup configuration
backup_config() {
    local backup_dir="/root/netbird-backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/netbird-config-$timestamp.tar.gz"

    print_status "Creating configuration backup..."

    # Create backup directory
    mkdir -p "$backup_dir"

    # Create backup
    if tar -czf "$backup_file" -C /opt/netbird . 2>/dev/null; then
        print_success "Configuration backed up to: $backup_file"

        # Keep only last 5 backups
        cd "$backup_dir"
        ls -t netbird-config-*.tar.gz | tail -n +6 | xargs rm -f 2>/dev/null

        print_status "Backup contents:"
        tar -tzf "$backup_file" | head -10

        if [ $(tar -tzf "$backup_file" | wc -l) -gt 10 ]; then
            print_status "... and $(( $(tar -tzf "$backup_file" | wc -l) - 10 )) more files"
        fi
    else
        print_error "Backup failed"
        return 1
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
    "cert-logs")
        show_cert_logs
        ;;
    "test")
        test_connectivity
        ;;
    "backup")
        backup_config
        ;;
    "azure-fix")
        print_status "Azure AD Configuration Guide"
        echo "════════════════════════════════════════"
        echo
        print_highlight "ℹ️  Current Configuration: SPA (Single Page Application)"
        echo "• No client secret required (uses PKCE flow)"
        echo "• Server-side user management disabled"
        echo "• Users authenticate directly via web dashboard"
        echo "• 'ClientSecret is missing' messages are NORMAL and expected"
        echo
        echo "Choose the appropriate fix based on your error:"
        echo
        print_highlight "🔧 For 403 Permission Errors (web dashboard login issues):"
        echo "1. Go to https://portal.azure.com"
        echo "2. Navigate to Azure Active Directory > App Registrations"
        echo "3. Find your NetBird application"
        echo "4. Go to API permissions"
        echo "5. Click '+ Add a permission'"
        echo "6. Select 'Microsoft Graph' > 'Delegated permissions'"
        echo "7. Add these permissions:"
        echo "   • User.Read"
        echo "   • openid"
        echo "   • profile"
        echo "   • email"
        echo "8. Click 'Grant admin consent for [your organization]'"
        echo "9. Wait for status to show 'Granted'"
        echo
        print_highlight "🔧 For AADSTS65005 (scope 'api' doesn't exist):"
        echo "1. Go to your Azure AD app > Expose an API"
        echo "2. Click 'Set' next to Application ID URI"
        echo "3. Accept default: api://[your-client-id]"
        echo "4. Click 'Add a scope'"
        echo "5. Scope name: api"
        echo "6. Who can consent: Admins only"
        echo "7. Admin consent display name: Access NetBird API"
        echo "8. Admin consent description: Allows access to NetBird API"
        echo "9. State: Enabled"
        echo "10. Click 'Add scope'"
        echo
        print_highlight "🔧 For AADSTS500011 (resource principal not found):"
        echo "1. Go to API permissions in your Azure AD app"
        echo "2. Click 'Grant admin consent for [organization]'"
        echo "3. Confirm by clicking 'Yes'"
        echo "4. Verify all permissions show 'Granted for [organization]'"
        echo "5. Ensure the app is properly registered in your tenant"
        echo
        print_highlight "ℹ️  Note about 'ClientSecret is missing' errors:"
        echo "These are normal for SPA configurations and do not need fixing."
        echo "SPA applications use PKCE flow and don't require client secrets."
        echo
        print_highlight "🔄 After making changes:"
        echo "1. Restart services: $0 restart"
        echo "2. Check logs: $0 logs | grep -i 'permission\\|403\\|graph\\|AADSTS'"
        echo "3. Test authentication via NetBird dashboard"
        ;;
    *)
        echo "Enhanced NetBird Management Script v2.1.0"
        echo "Usage: $0 {status|health|logs|restart|stop|start|update|ssl|cert-logs|test|backup|azure-fix}"
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
        echo "  cert-logs   - Show SSL certificate generation logs"
        echo "  test        - Test domain connectivity and SSL"
        echo "  backup      - Create configuration backup"
        echo "  azure-fix   - Show Azure AD authentication fix instructions"
        echo ""
        echo "Using: $DOCKER_COMPOSE_CMD"
        echo "Config: $NETBIRD_CONFIG"
        echo "Domain: $(get_netbird_domain)"
        ;;
esac
