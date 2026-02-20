#!/usr/bin/env bash

# NetBird Self-Hosted Management Script
# Helper script for managing NetBird self-hosted deployment

set -e

VERSION="3.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_NAME="netbird-selfhosted"

# Source shared libraries
source "${SCRIPT_DIR}/lib/output-helpers.sh"

# Function to check prerequisites
check_prerequisites() {
    if ! command -v hcloud >/dev/null 2>&1; then
        print_error "hcloud CLI is not installed!"
        exit 1
    fi

    if ! hcloud server list >/dev/null 2>&1; then
        print_error "Cannot connect to Hetzner Cloud API!"
        exit 1
    fi
}

# Function to check if server exists
server_exists() {
    hcloud server describe "$SERVER_NAME" >/dev/null 2>&1
}

# Function to get server status
get_server_status() {
    if server_exists; then
        hcloud server describe "$SERVER_NAME" -o json | jq -r '.status // "unknown"'
    else
        echo "not_found"
    fi
}

# Function to get server IP
get_server_ip() {
    if server_exists; then
        hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip // ""'
    else
        echo ""
    fi
}

# Function to show server info
show_server_info() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    print_header "=== NetBird Self-Hosted Server Information ==="
    echo

    local info=$(hcloud server describe "$SERVER_NAME" -o json)
    local status=$(echo "$info" | jq -r '.status // "unknown"')
    local ip=$(echo "$info" | jq -r '.public_net.ipv4.ip // ""')
    local type=$(echo "$info" | jq -r '.server_type.name // ""')
    local location=$(echo "$info" | jq -r '.datacenter.location.name // ""')
    local created=$(echo "$info" | jq -r '.created // ""')

    echo "Name: $SERVER_NAME"
    echo "Status: $status"
    echo "Type: $type"
    echo "Location: $location"
    echo "IPv4: $ip"
    echo "Created: $created"
    echo

    # Test SSH connectivity
    print_status "Testing SSH connectivity..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new root@$ip "echo 'SSH connection successful'" >/dev/null 2>&1; then
        echo "SSH: ✅ Connected"
    else
        echo "SSH: ❌ Cannot connect"
    fi

    # Check NetBird services if server is running
    if [ "$status" = "running" ]; then
        print_status "Checking NetBird services..."
        local services_count=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new root@$ip "cd /opt/netbird/netbird/infrastructure_files/artifacts/ && docker compose ps --filter status=running --quiet 2>/dev/null | wc -l" 2>/dev/null || echo "0")

        if [ "$services_count" -ge "4" ]; then
            echo "NetBird Services: ✅ Running ($services_count services)"
        else
            echo "NetBird Services: ⚠️  Some services may be down ($services_count/4 running)"
        fi
    fi

    echo "==================="
}

# Function to connect via SSH
connect_ssh() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" != "running" ]; then
        print_error "Server is not running (status: $status)"
        return 1
    fi

    local ip=$(get_server_ip)
    print_status "Connecting to NetBird server $SERVER_NAME ($ip)..."

    if [ ! -f ~/.ssh/id_rsa ]; then
        print_error "SSH private key not found at ~/.ssh/id_rsa"
        return 1
    fi

    ssh -o StrictHostKeyChecking=accept-new root@$ip
}

# Function to show NetBird service status
show_service_status() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" != "running" ]; then
        print_error "Server is not running (status: $status)"
        return 1
    fi

    local ip=$(get_server_ip)
    print_status "Checking NetBird service status on $SERVER_NAME..."

    ssh -o StrictHostKeyChecking=accept-new root@$ip << 'EOF'
echo "=== NetBird Service Status ==="
cd /opt/netbird/netbird/infrastructure_files/artifacts/
docker compose ps
echo
echo "=== Resource Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
EOF
}

# Function to show NetBird logs
show_logs() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" != "running" ]; then
        print_error "Server is not running (status: $status)"
        return 1
    fi

    local ip=$(get_server_ip)
    local service="${1:-all}"

    print_status "Showing NetBird logs for: $service"

    if [ "$service" = "all" ]; then
        ssh -o StrictHostKeyChecking=accept-new root@$ip "cd /opt/netbird/netbird/infrastructure_files/artifacts/ && docker compose logs --tail=50"
    else
        ssh -o StrictHostKeyChecking=accept-new root@$ip "cd /opt/netbird/netbird/infrastructure_files/artifacts/ && docker compose logs --tail=50 $service"
    fi
}

# Function to restart NetBird services
restart_services() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" != "running" ]; then
        print_error "Server is not running (status: $status)"
        return 1
    fi

    local ip=$(get_server_ip)
    print_status "Restarting NetBird services..."

    ssh -o StrictHostKeyChecking=accept-new root@$ip << 'EOF'
cd /opt/netbird/netbird/infrastructure_files/artifacts/
echo "Restarting NetBird services..."
docker compose restart
echo "Services restarted successfully"
docker compose ps
EOF

    print_success "NetBird services restarted"
}

# Function to update NetBird
update_netbird() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" != "running" ]; then
        print_error "Server is not running (status: $status)"
        return 1
    fi

    local ip=$(get_server_ip)
    print_status "Updating NetBird to latest version..."

    ssh -o StrictHostKeyChecking=accept-new root@$ip << 'EOF'
cd /opt/netbird/netbird/infrastructure_files/artifacts/
echo "=== NetBird Update Process ==="

# Backup current configuration
echo "Creating backup..."
cp -r . /opt/netbird/backup-$(date +%Y%m%d-%H%M%S)/

# Pull latest images
echo "Pulling latest Docker images..."
docker compose pull

# Restart with new images
echo "Restarting services with updated images..."
docker compose up -d --force-recreate

echo "Update completed successfully!"
docker compose ps
EOF

    print_success "NetBird updated successfully"
}

# Function to backup NetBird configuration
backup_netbird() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" != "running" ]; then
        print_error "Server is not running (status: $status)"
        return 1
    fi

    local ip=$(get_server_ip)
    local backup_name="netbird-backup-$(date +%Y%m%d-%H%M%S)"

    print_status "Creating NetBird backup: $backup_name"

    ssh -o StrictHostKeyChecking=accept-new root@$ip << EOF
cd /opt/netbird/netbird/infrastructure_files/artifacts/
mkdir -p /opt/netbird/backups/$backup_name

echo "Stopping management service for backup..."
docker compose stop management

echo "Copying configuration files..."
cp docker-compose.yml turnserver.conf management.json /opt/netbird/backups/$backup_name/

echo "Backing up management database..."
docker compose cp -a management:/var/lib/netbird/ /opt/netbird/backups/$backup_name/

echo "Restarting management service..."
docker compose start management

echo "Backup created at: /opt/netbird/backups/$backup_name"
ls -la /opt/netbird/backups/$backup_name/
EOF

    print_success "Backup created: $backup_name"
}

# Function to show dashboard access info
show_dashboard_info() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local ip=$(get_server_ip)

    print_header "=== NetBird Dashboard Access ==="
    echo

    # Try to get domain from server configuration
    local domain=""
    if [ "$(get_server_status)" = "running" ]; then
        domain=$(ssh -o StrictHostKeyChecking=accept-new root@$ip "grep NETBIRD_DOMAIN /opt/netbird/netbird/infrastructure_files/setup.env 2>/dev/null | cut -d'=' -f2 | tr -d '\"'" 2>/dev/null || echo "")
    fi

    if [ -n "$domain" ]; then
        echo "Dashboard URL: https://$domain"
        echo "Management API: https://$domain/api"
        echo
        echo "To access the dashboard:"
        echo "1. Ensure DNS points $domain to $ip"
        echo "2. Wait for SSL certificate generation (5-10 minutes)"
        echo "3. Open https://$domain in your browser"
        echo "4. Sign in with your Azure AD account"
    else
        echo "Domain not configured or server not accessible"
        echo "Server IP: $ip"
        echo "SSH to server to check configuration:"
        echo "  ssh root@$ip"
        echo "  cat /opt/netbird/netbird/infrastructure_files/setup.env"
    fi
    echo "==================="
}

# Function to start server
start_server() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" = "running" ]; then
        print_warning "Server is already running"
        return 0
    fi

    print_status "Starting NetBird server..."
    hcloud server poweron "$SERVER_NAME"
    print_success "Server start command sent"
}

# Function to stop server
stop_server() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    local status=$(get_server_status)
    if [ "$status" = "off" ]; then
        print_warning "Server is already stopped"
        return 0
    fi

    print_status "Stopping NetBird server..."
    hcloud server poweroff "$SERVER_NAME"
    print_success "Server stop command sent"
}

# Function to delete server
delete_server() {
    if ! server_exists; then
        print_error "NetBird server '$SERVER_NAME' not found!"
        return 1
    fi

    print_warning "This will permanently delete the NetBird server '$SERVER_NAME'"
    print_warning "All NetBird data and configuration will be lost!"
    echo
    read -p "Are you sure? Type 'DELETE' to confirm: " -r
    if [ "$REPLY" = "DELETE" ]; then
        print_status "Deleting NetBird server..."
        hcloud server delete "$SERVER_NAME"
        print_success "NetBird server deleted successfully"
    else
        print_status "Deletion cancelled"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
NetBird Self-Hosted Management Script v$VERSION

Usage: $0 <command>

Commands:
  info          Show server information and status
  ssh           Connect to server via SSH
  status        Show NetBird service status
  logs [service] Show logs (all services or specific: management, signal, coturn, dashboard)
  restart       Restart NetBird services
  update        Update NetBird to latest version
  backup        Create configuration and data backup
  dashboard     Show dashboard access information
  start         Start the server
  stop          Stop the server
  delete        Delete the server (DANGEROUS)
  help          Show this help message

Examples:
  $0 info                    # Show server details
  $0 ssh                     # Connect to server
  $0 status                  # Check service status
  $0 logs                    # Show all logs
  $0 logs management         # Show management service logs
  $0 restart                 # Restart all services
  $0 update                  # Update NetBird
  $0 backup                  # Create backup
  $0 dashboard               # Show dashboard info

Server management:
  $0 start                   # Power on server
  $0 stop                    # Power off server (saves costs)
  $0 delete                  # Delete server permanently

Cost optimization:
  - Stop server when not in use: $0 stop
  - Monthly cost: ~€6.33 (server + IPv4)
  - Delete when done: $0 delete
EOF
}

# Main function
main() {
    check_prerequisites

    case "${1:-help}" in
        "info")
            show_server_info
            ;;
        "ssh")
            connect_ssh
            ;;
        "status")
            show_service_status
            ;;
        "logs")
            show_logs "$2"
            ;;
        "restart")
            restart_services
            ;;
        "update")
            update_netbird
            ;;
        "backup")
            backup_netbird
            ;;
        "dashboard")
            show_dashboard_info
            ;;
        "start")
            start_server
            ;;
        "stop")
            stop_server
            ;;
        "delete")
            delete_server
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Unknown command: $1"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
