#!/usr/bin/env bash
# netbird-config.sh - NetBird setup.env generation and configuration helpers
# Generates the setup.env file for NetBird self-hosted deployments using
# Microsoft Entra ID (Azure AD) as the identity provider.

# Source guard - prevent double-sourcing
[[ -n "${_NETBIRD_CONFIG_LOADED:-}" ]] && return 0; _NETBIRD_CONFIG_LOADED=1

# Source shared output helpers
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/output-helpers.sh"

# ---------------------------------------------------------------------------
# generate_setup_env - Generate the NetBird setup.env configuration file
#
# Reads from environment variables and writes a setup.env file suitable for
# the NetBird docker-compose deployment with Microsoft Entra ID (Azure AD).
#
# Required environment variables (checked before writing):
#   NETBIRD_DOMAIN                     - The domain for NetBird (e.g. netbird.example.com)
#   ENTRA_TENANT_ID or AZURE_TENANT_ID - Microsoft Entra tenant ID (UUID)
#   ENTRA_SPA_CLIENT_ID or AZURE_CLIENT_ID - SPA app registration client ID (UUID)
#
# Optional environment variables:
#   ENTRA_MGMT_CLIENT_ID      - Management API client ID
#   ENTRA_MGMT_CLIENT_SECRET  - Management API client secret
#   ENTRA_MGMT_OBJECT_ID      - Management API service principal object ID
#
# Arguments:
#   $1 - output_path: Path where setup.env will be written
#
# Returns 0 on success, 1 if required variables are missing.
# ---------------------------------------------------------------------------
generate_setup_env() {
    local output_path="$1"

    if [[ -z "$output_path" ]]; then
        print_error "Usage: generate_setup_env <output_path>"
        return 1
    fi

    # Resolve required variables (support both naming conventions)
    local domain="${NETBIRD_DOMAIN:-}"
    local tenant_id="${ENTRA_TENANT_ID:-${AZURE_TENANT_ID:-}}"
    local client_id="${ENTRA_SPA_CLIENT_ID:-${AZURE_CLIENT_ID:-}}"

    # Resolve optional management variables
    local mgmt_client_id="${ENTRA_MGMT_CLIENT_ID:-}"
    local mgmt_secret="${ENTRA_MGMT_CLIENT_SECRET:-}"
    local mgmt_object_id="${ENTRA_MGMT_OBJECT_ID:-}"

    # Validate required variables
    local missing=0

    if [[ -z "$domain" ]]; then
        print_error "NETBIRD_DOMAIN is not set"
        missing=1
    fi

    if [[ -z "$tenant_id" ]]; then
        print_error "ENTRA_TENANT_ID (or AZURE_TENANT_ID) is not set"
        missing=1
    fi

    if [[ -z "$client_id" ]]; then
        print_error "ENTRA_SPA_CLIENT_ID (or AZURE_CLIENT_ID) is not set"
        missing=1
    fi

    if [[ $missing -ne 0 ]]; then
        print_error "Cannot generate setup.env: required variables are missing"
        return 1
    fi

    print_status "Generating setup.env at $output_path ..."

    # Write the setup.env file
    cat > "$output_path" <<SETUP_ENV
NETBIRD_DOMAIN="${domain}"
NETBIRD_MGMT_IDP="azure"
NETBIRD_AUTH_CLIENT_ID="${client_id}"
NETBIRD_AUTH_AUTHORITY="https://login.microsoftonline.com/${tenant_id}/v2.0"
NETBIRD_AUTH_AUDIENCE="${client_id}"
NETBIRD_AUTH_REDIRECT_URI=""
NETBIRD_AUTH_SILENT_REDIRECT_URI=""
NETBIRD_AUTH_SUPPORTED_SCOPES="openid profile email offline_access api://${client_id}/api"
NETBIRD_USE_AUTH0=false
NETBIRD_MGMT_API_ENDPOINT="https://${domain}:443"
NETBIRD_MGMT_SINGLE_ACCOUNT_MODE=true
NETBIRD_IDP_MGMT_CLIENT_ID="${mgmt_client_id}"
NETBIRD_IDP_MGMT_CLIENT_SECRET="${mgmt_secret}"
NETBIRD_IDP_MGMT_EXTRA_OBJECT_ID="${mgmt_object_id}"
NETBIRD_IDP_MGMT_EXTRA_GRAPH_API_ENDPOINT="https://graph.microsoft.com/v1.0"
SETUP_ENV

    # Secure the file - contains secrets
    chmod 0600 "$output_path"

    print_success "setup.env written to $output_path (mode 0600)"
    return 0
}

# ---------------------------------------------------------------------------
# apply_nginx_spa_fix - Fix nginx SPA routing in a NetBird deployment
#
# Addresses the common issue where direct URL access to the NetBird dashboard
# returns a 404 because nginx doesn't fall back to index.html for client-side
# routes.
#
# Arguments:
#   $1 - server_ip: IP address of the NetBird server
#
# Returns 0 on success.
# ---------------------------------------------------------------------------
apply_nginx_spa_fix() {
    local server_ip="$1"

    if [[ -z "$server_ip" ]]; then
        print_error "Usage: apply_nginx_spa_fix <server_ip>"
        return 1
    fi

    print_status "Applying nginx SPA routing fix on $server_ip ..."

    # Check if Docker is running on the remote server
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "root@${server_ip}" \
        "docker ps >/dev/null 2>&1"; then
        print_error "Docker is not running on $server_ip or SSH access failed"
        return 1
    fi

    # Find the nginx container (usually named something like *nginx* or *caddy*)
    local nginx_container
    nginx_container=$(ssh -o BatchMode=yes "root@${server_ip}" \
        "docker ps --format '{{.Names}}' | grep -i nginx | head -1" 2>/dev/null)

    if [[ -z "$nginx_container" ]]; then
        print_warning "No nginx container found on $server_ip"
        print_status "Looking for containers with 'dashboard' in the name..."
        nginx_container=$(ssh -o BatchMode=yes "root@${server_ip}" \
            "docker ps --format '{{.Names}}' | grep -i dashboard | head -1" 2>/dev/null)
    fi

    if [[ -z "$nginx_container" ]]; then
        print_error "Could not find nginx or dashboard container on $server_ip"
        return 1
    fi

    print_status "Found container: $nginx_container"

    # Apply the SPA fix: add try_files directive for the dashboard location
    # This ensures that client-side routes (e.g. /peers, /settings) serve index.html
    # instead of returning 404.
    ssh -o BatchMode=yes "root@${server_ip}" bash <<'REMOTE_SCRIPT'
set -e

CONTAINER_NAME="$(docker ps --format '{{.Names}}' | grep -i nginx | head -1)"
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME="$(docker ps --format '{{.Names}}' | grep -i dashboard | head -1)"
fi

# Find the nginx config file inside the container
CONFIG_FILE=$(docker exec "$CONTAINER_NAME" find /etc/nginx -name "*.conf" -exec grep -l "location" {} \; 2>/dev/null | head -1)

if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: Could not find nginx config with location blocks"
    exit 1
fi

echo "Modifying $CONFIG_FILE in container $CONTAINER_NAME"

# Check if the fix is already applied
if docker exec "$CONTAINER_NAME" grep -q 'try_files.*index.html' "$CONFIG_FILE" 2>/dev/null; then
    echo "SPA fix is already applied"
    exit 0
fi

# Back up the original config
docker exec "$CONTAINER_NAME" cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Add try_files directive to location blocks serving the dashboard
docker exec "$CONTAINER_NAME" sed -i \
    '/location \/ {/,/}/ s|^\([[:space:]]*\)index .*|&\n\1try_files $uri $uri/ /index.html;|' \
    "$CONFIG_FILE"

# Reload nginx
docker exec "$CONTAINER_NAME" nginx -s reload 2>/dev/null || \
    docker restart "$CONTAINER_NAME"

echo "SPA fix applied and nginx reloaded"
REMOTE_SCRIPT

    if [[ $? -eq 0 ]]; then
        print_success "Nginx SPA routing fix applied on $server_ip"
        print_status "  Container: $nginx_container"
        print_status "  Change: Added 'try_files \$uri \$uri/ /index.html;' to dashboard location"
        return 0
    else
        print_error "Failed to apply nginx SPA fix on $server_ip"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# validate_netbird_config - Validate a NetBird setup.env file
#
# Reads the setup.env file and checks that all required variables are set,
# UUIDs are in the correct format, and the domain is valid.
#
# Arguments:
#   $1 - setup_env_path: Path to the setup.env file
#
# Returns 0 if valid, 1 if any validation errors are found.
# ---------------------------------------------------------------------------
validate_netbird_config() {
    local setup_env_path="$1"

    if [[ -z "$setup_env_path" ]]; then
        print_error "Usage: validate_netbird_config <setup_env_path>"
        return 1
    fi

    if [[ ! -f "$setup_env_path" ]]; then
        print_error "File not found: $setup_env_path"
        return 1
    fi

    print_status "Validating NetBird config: $setup_env_path"

    # Source the env file to get variable values
    local netbird_domain=""
    local netbird_auth_client_id=""
    local netbird_auth_authority=""
    local netbird_mgmt_api_endpoint=""
    local netbird_idp_mgmt_client_id=""
    local netbird_idp_mgmt_client_secret=""

    # Read variables from the file without polluting the current shell
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Remove surrounding quotes from value
        value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')

        case "$key" in
            NETBIRD_DOMAIN)               netbird_domain="$value" ;;
            NETBIRD_AUTH_CLIENT_ID)        netbird_auth_client_id="$value" ;;
            NETBIRD_AUTH_AUTHORITY)        netbird_auth_authority="$value" ;;
            NETBIRD_MGMT_API_ENDPOINT)    netbird_mgmt_api_endpoint="$value" ;;
            NETBIRD_IDP_MGMT_CLIENT_ID)   netbird_idp_mgmt_client_id="$value" ;;
            NETBIRD_IDP_MGMT_CLIENT_SECRET) netbird_idp_mgmt_client_secret="$value" ;;
        esac
    done < "$setup_env_path"

    local errors=0

    # UUID regex pattern (8-4-4-4-12 hex digits)
    local uuid_regex='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    # Domain regex pattern (basic validation)
    local domain_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'

    # Check required: NETBIRD_DOMAIN
    if [[ -z "$netbird_domain" ]]; then
        print_error "NETBIRD_DOMAIN is empty or not set"
        errors=$((errors + 1))
    elif [[ ! "$netbird_domain" =~ $domain_regex ]]; then
        print_error "NETBIRD_DOMAIN has invalid format: '$netbird_domain'"
        errors=$((errors + 1))
    fi

    # Check required: NETBIRD_AUTH_CLIENT_ID (should be a UUID)
    if [[ -z "$netbird_auth_client_id" ]]; then
        print_error "NETBIRD_AUTH_CLIENT_ID is empty or not set"
        errors=$((errors + 1))
    elif [[ ! "$netbird_auth_client_id" =~ $uuid_regex ]]; then
        print_error "NETBIRD_AUTH_CLIENT_ID is not a valid UUID: '$netbird_auth_client_id'"
        errors=$((errors + 1))
    fi

    # Check required: NETBIRD_AUTH_AUTHORITY (should contain a tenant UUID)
    if [[ -z "$netbird_auth_authority" ]]; then
        print_error "NETBIRD_AUTH_AUTHORITY is empty or not set"
        errors=$((errors + 1))
    else
        # Extract tenant ID from the authority URL
        local tenant_id_from_authority
        tenant_id_from_authority=$(echo "$netbird_auth_authority" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
        if [[ -z "$tenant_id_from_authority" ]]; then
            print_error "NETBIRD_AUTH_AUTHORITY does not contain a valid tenant UUID: '$netbird_auth_authority'"
            errors=$((errors + 1))
        fi
    fi

    # Check required: NETBIRD_MGMT_API_ENDPOINT
    if [[ -z "$netbird_mgmt_api_endpoint" ]]; then
        print_error "NETBIRD_MGMT_API_ENDPOINT is empty or not set"
        errors=$((errors + 1))
    fi

    # Validate optional management client ID if set
    if [[ -n "$netbird_idp_mgmt_client_id" && ! "$netbird_idp_mgmt_client_id" =~ $uuid_regex ]]; then
        print_warning "NETBIRD_IDP_MGMT_CLIENT_ID is set but not a valid UUID: '$netbird_idp_mgmt_client_id'"
        errors=$((errors + 1))
    fi

    # Warn if management secret is empty (optional but recommended)
    if [[ -z "$netbird_idp_mgmt_client_secret" ]]; then
        print_warning "NETBIRD_IDP_MGMT_CLIENT_SECRET is not set (optional, needed for user sync)"
    fi

    # Summary
    if [[ $errors -eq 0 ]]; then
        print_success "NetBird config is valid: $setup_env_path"
        return 0
    else
        print_error "NetBird config has $errors error(s)"
        return 1
    fi
}
