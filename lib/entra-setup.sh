#!/usr/bin/env bash
# entra-setup.sh - Automates Entra ID (Azure AD) app registration for Netbird using Azure CLI
# Source this file from deploy scripts: source "${LIB_DIR}/entra-setup.sh"

# Prevent double-sourcing
[[ -n "${_ENTRA_SETUP_LOADED:-}" ]] && return 0
_ENTRA_SETUP_LOADED=1

# Resolve library directory and source output helpers
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/output-helpers.sh"

# Project root (one level above lib/)
PROJECT_ROOT="$(cd "${LIB_DIR}/.." && pwd)"

# Fallback credentials directory for storing management app secrets
ENTRA_CREDS_DIR="${PROJECT_ROOT}/.entra-credentials"

###############################################################################
# Well-known Microsoft Graph Permission IDs
###############################################################################

# Delegated permissions (Scope)
readonly GRAPH_USER_READ="e1fe6dd8-ba31-4d61-89e7-88639da4683d"
readonly GRAPH_OPENID="37f7f235-527c-4136-accd-4a02d197296e"
readonly GRAPH_PROFILE="14dad69e-099b-42c9-810b-d002981feec1"
readonly GRAPH_EMAIL="64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"
readonly GRAPH_OFFLINE_ACCESS="7427e0e9-2fba-42fe-b0c0-848c9e6a8182"
readonly GRAPH_USER_READ_ALL_DELEGATED="a154be20-db9c-4678-8ab7-66f6cc099a59"

# Application permissions (Role)
readonly GRAPH_USER_READ_ALL_APP="df021288-bdef-4463-88db-98f22de89214"
readonly GRAPH_DIRECTORY_READ_ALL_APP="7ab1d382-f21e-4acd-a863-ba3e13f7da61"

# Microsoft Graph resource application ID
readonly MS_GRAPH_RESOURCE="00000003-0000-0000-c000-000000000000"

###############################################################################
# Exported state variables (populated by setup functions)
###############################################################################

ENTRA_TENANT_ID=""
ENTRA_SPA_CLIENT_ID=""
ENTRA_SPA_OBJECT_ID=""
ENTRA_MGMT_CLIENT_ID=""
ENTRA_MGMT_OBJECT_ID=""
ENTRA_MGMT_CLIENT_SECRET=""

###############################################################################
# Rollback Mechanism
###############################################################################

_ENTRA_ROLLBACK_STACK=()

_entra_rollback() {
    if [[ ${#_ENTRA_ROLLBACK_STACK[@]} -eq 0 ]]; then
        return 0
    fi

    print_warning "An error occurred. Rolling back Entra ID changes..."
    echo ""

    local i
    for (( i=${#_ENTRA_ROLLBACK_STACK[@]}-1; i>=0; i-- )); do
        local cmd="${_ENTRA_ROLLBACK_STACK[$i]}"
        print_status "Rollback: ${cmd}"
        if eval "${cmd}" >/dev/null 2>&1; then
            print_success "Rolled back successfully."
        else
            print_warning "Rollback command failed (resource may already be deleted): ${cmd}"
        fi
    done

    _ENTRA_ROLLBACK_STACK=()
    print_status "Rollback complete."
}

# Trap ERR to trigger rollback on any unhandled failure
trap '_entra_rollback' ERR

###############################################################################
# 1. entra_check_az_cli
#    Returns: 0 = ready, 1 = az not installed, 2 = not logged in
###############################################################################

entra_check_az_cli() {
    if ! command -v az >/dev/null 2>&1; then
        print_error "Azure CLI (az) is not installed."
        print_status "Install it: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi

    if ! az account show >/dev/null 2>&1; then
        print_warning "Azure CLI is installed but you are not logged in."
        return 2
    fi

    print_success "Azure CLI is installed and authenticated."
    return 0
}

###############################################################################
# 2. entra_login
#    Logs in via device code flow, selects tenant, stores ENTRA_TENANT_ID
###############################################################################

entra_login() {
    print_header "Logging in to Azure..."
    echo ""
    print_status "Sign in with an admin account for the target tenant."
    echo ""

    # Try interactive browser login first (supports device compliance/Conditional Access)
    # Fall back to device-code flow for headless/remote machines
    if ! az login --allow-no-subscriptions --output none 2>/dev/null; then
        print_status "Interactive login failed. Falling back to device code flow..."
        if ! az login --use-device-code --allow-no-subscriptions --output none; then
            print_error "Azure login failed."
            return 1
        fi
    fi

    ENTRA_TENANT_ID="$(az account show --query tenantId -o tsv 2>/dev/null)"
    if [[ -z "$ENTRA_TENANT_ID" ]]; then
        print_error "Failed to determine tenant ID from login."
        return 1
    fi

    print_success "Logged in to tenant: ${ENTRA_TENANT_ID}"
    return 0
}

###############################################################################
# 3. entra_create_spa_app(domain, project_name)
#    Creates the SPA app registration for Netbird
###############################################################################

entra_create_spa_app() {
    local domain="$1"
    local project_name="$2"

    if [[ -z "$domain" || -z "$project_name" ]]; then
        print_error "Usage: entra_create_spa_app <domain> <project_name>"
        return 1
    fi

    print_header "Creating Netbird SPA App Registration..."
    echo ""

    # ---- Create the app registration ----
    print_status "Creating app: NetBird ${project_name}..."
    local app_json
    app_json="$(az ad app create \
        --display-name "NetBird ${project_name}" \
        --sign-in-audience AzureADMyOrg 2>/dev/null)"
    if [[ $? -ne 0 || -z "$app_json" ]]; then
        print_error "Failed to create app registration."
        return 1
    fi

    local APP_ID
    APP_ID="$(echo "${app_json}" | jq -r '.appId')"
    if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
        print_error "Failed to extract app ID from registration response."
        return 1
    fi

    # Push rollback for app deletion
    _ENTRA_ROLLBACK_STACK+=("az ad app delete --id ${APP_ID}")

    print_success "App registered with Client ID: ${APP_ID}"

    # ---- Get object ID (needed for Graph REST API calls) ----
    local OBJECT_ID
    OBJECT_ID="$(az ad app show --id "${APP_ID}" --query id -o tsv 2>/dev/null)"
    if [[ -z "$OBJECT_ID" ]]; then
        print_error "Failed to retrieve object ID for app."
        return 1
    fi
    print_status "Object ID: ${OBJECT_ID}"

    # ---- Enable token issuance ----
    print_status "Enabling ID token and access token issuance..."
    if ! az ad app update --id "${APP_ID}" \
        --enable-id-token-issuance true \
        --enable-access-token-issuance true >/dev/null 2>&1; then
        print_error "Failed to enable token issuance."
        return 1
    fi
    print_success "Token issuance enabled."

    # ---- Set SPA redirect URIs ----
    print_status "Configuring SPA redirect URIs..."
    if ! az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications/${OBJECT_ID}" \
        --headers "Content-Type=application/json" \
        --body "{\"spa\":{\"redirectUris\":[\"https://${domain}/auth\",\"https://${domain}/silent-auth\"]}}"; then
        print_error "Failed to set SPA redirect URIs."
        return 1
    fi
    print_success "SPA redirect URIs configured."

    # ---- Set public client redirect URIs ----
    print_status "Configuring public client redirect URIs..."
    if ! az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications/${OBJECT_ID}" \
        --headers "Content-Type=application/json" \
        --body "{\"publicClient\":{\"redirectUris\":[\"https://login.microsoftonline.com/common/oauth2/nativeclient\",\"http://localhost:53000\"]}}"; then
        print_error "Failed to set public client redirect URIs."
        return 1
    fi
    print_success "Public client redirect URIs configured."

    # ---- Set identifier URI and public client fallback ----
    print_status "Setting identifier URI and enabling public client fallback..."
    if ! az ad app update --id "${APP_ID}" \
        --identifier-uris "api://${APP_ID}" \
        --is-fallback-public-client true >/dev/null 2>&1; then
        print_error "Failed to set identifier URI or public client fallback."
        return 1
    fi
    print_success "Identifier URI set to: api://${APP_ID}"

    # ---- Add delegated API permissions (Microsoft Graph) ----
    print_status "Adding delegated Microsoft Graph permissions..."
    local permissions_json
    permissions_json="$(cat <<PERMS_EOF
[{"resourceAppId":"${MS_GRAPH_RESOURCE}","resourceAccess":[
  {"id":"${GRAPH_USER_READ}","type":"Scope"},
  {"id":"${GRAPH_USER_READ_ALL_DELEGATED}","type":"Scope"},
  {"id":"${GRAPH_OFFLINE_ACCESS}","type":"Scope"},
  {"id":"${GRAPH_OPENID}","type":"Scope"},
  {"id":"${GRAPH_PROFILE}","type":"Scope"},
  {"id":"${GRAPH_EMAIL}","type":"Scope"}
]}]
PERMS_EOF
)"

    if ! az ad app update --id "${APP_ID}" \
        --required-resource-accesses "${permissions_json}" >/dev/null 2>&1; then
        print_error "Failed to add delegated API permissions."
        return 1
    fi
    print_success "Delegated permissions added (User.Read, User.Read.All, offline_access, openid, profile, email)."

    # ---- Add custom API scope via Graph REST API ----
    print_status "Adding custom API scope (api)..."
    local scope_id
    scope_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"

    local scope_body
    scope_body="$(cat <<SCOPE_EOF
{
  "api": {
    "oauth2PermissionScopes": [
      {
        "id": "${scope_id}",
        "adminConsentDescription": "NetBird API access",
        "adminConsentDisplayName": "api",
        "isEnabled": true,
        "type": "User",
        "userConsentDescription": "Access NetBird API",
        "userConsentDisplayName": "api",
        "value": "api"
      }
    ]
  }
}
SCOPE_EOF
)"

    if ! az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications/${OBJECT_ID}" \
        --headers "Content-Type=application/json" \
        --body "${scope_body}" >/dev/null 2>&1; then
        print_error "Failed to add custom API scope."
        return 1
    fi
    print_success "Custom API scope 'api' added."

    # ---- Create service principal ----
    print_status "Creating service principal..."
    local sp_json
    sp_json="$(az ad sp create --id "${APP_ID}" 2>&1)"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create service principal."
        print_error "${sp_json}"
        return 1
    fi

    local SP_ID
    SP_ID="$(echo "${sp_json}" | jq -r '.id')"
    if [[ -n "$SP_ID" && "$SP_ID" != "null" ]]; then
        _ENTRA_ROLLBACK_STACK+=("az ad sp delete --id ${SP_ID}")
    fi
    print_success "Service principal created."

    # ---- Grant admin consent ----
    print_status "Granting admin consent for API permissions..."
    if ! az ad app permission admin-consent --id "${APP_ID}" >/dev/null 2>&1; then
        print_warning "Admin consent may require Global Administrator privileges."
        print_warning "You can grant consent later in the Azure Portal."
    else
        print_success "Admin consent granted."
    fi

    # ---- Store results ----
    ENTRA_SPA_CLIENT_ID="${APP_ID}"
    ENTRA_SPA_OBJECT_ID="${OBJECT_ID}"

    echo ""
    print_success "SPA app registration complete."
    print_highlight "  Client ID (App ID): ${ENTRA_SPA_CLIENT_ID}"
    print_highlight "  Object ID:          ${ENTRA_SPA_OBJECT_ID}"
    echo ""

    return 0
}

###############################################################################
# 4. entra_create_management_app(project_name, [vault])
#    Creates the management/backend app registration with client secret
###############################################################################

entra_create_management_app() {
    local project_name="$1"
    local vault="${2:-}"

    if [[ -z "$project_name" ]]; then
        print_error "Usage: entra_create_management_app <project_name> [vault]"
        return 1
    fi

    print_header "Creating Netbird Management App Registration..."
    echo ""

    # ---- Create the app registration ----
    print_status "Creating app: NetBird Management ${project_name}..."
    local mgmt_json
    mgmt_json="$(az ad app create \
        --display-name "NetBird Management ${project_name}" \
        --sign-in-audience AzureADMyOrg 2>/dev/null)"
    if [[ $? -ne 0 || -z "$mgmt_json" ]]; then
        print_error "Failed to create management app registration."
        return 1
    fi

    local MGMT_APP_ID
    MGMT_APP_ID="$(echo "${mgmt_json}" | jq -r '.appId')"
    if [[ -z "$MGMT_APP_ID" || "$MGMT_APP_ID" == "null" ]]; then
        print_error "Failed to extract app ID from management app response."
        return 1
    fi

    # Push rollback for app deletion
    _ENTRA_ROLLBACK_STACK+=("az ad app delete --id ${MGMT_APP_ID}")

    local MGMT_OBJECT_ID
    MGMT_OBJECT_ID="$(az ad app show --id "${MGMT_APP_ID}" --query id -o tsv 2>/dev/null)"
    if [[ -z "$MGMT_OBJECT_ID" ]]; then
        print_error "Failed to retrieve object ID for management app."
        return 1
    fi

    print_success "Management app registered with Client ID: ${MGMT_APP_ID}"
    print_status "Object ID: ${MGMT_OBJECT_ID}"

    # ---- Generate client secret ----
    print_status "Generating client secret (valid for 2 years)..."
    local secret_json
    secret_json="$(az ad app credential reset \
        --id "${MGMT_APP_ID}" \
        --append \
        --display-name "NetBird Management Secret" \
        --years 2 2>/dev/null)"
    if [[ $? -ne 0 || -z "$secret_json" ]]; then
        print_error "Failed to generate client secret."
        return 1
    fi

    local CLIENT_SECRET
    CLIENT_SECRET="$(echo "${secret_json}" | jq -r '.password')"
    if [[ -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
        print_error "Failed to extract client secret from response."
        return 1
    fi
    print_success "Client secret generated."

    # ---- Add application permissions (Graph User.Read.All + Directory.Read.All) ----
    print_status "Adding application permissions (User.Read.All, Directory.Read.All)..."
    local mgmt_permissions_json
    mgmt_permissions_json="$(cat <<MGMT_PERMS_EOF
[{"resourceAppId":"${MS_GRAPH_RESOURCE}","resourceAccess":[
  {"id":"${GRAPH_USER_READ_ALL_APP}","type":"Role"},
  {"id":"${GRAPH_DIRECTORY_READ_ALL_APP}","type":"Role"}
]}]
MGMT_PERMS_EOF
)"

    if ! az ad app update --id "${MGMT_APP_ID}" \
        --required-resource-accesses "${mgmt_permissions_json}" >/dev/null 2>&1; then
        print_error "Failed to add application permissions."
        return 1
    fi
    print_success "Application permissions added."

    # ---- Create service principal ----
    print_status "Creating service principal for management app..."
    local mgmt_sp_json
    mgmt_sp_json="$(az ad sp create --id "${MGMT_APP_ID}" 2>&1)"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create service principal for management app."
        print_error "${mgmt_sp_json}"
        return 1
    fi

    local MGMT_SP_ID
    MGMT_SP_ID="$(echo "${mgmt_sp_json}" | jq -r '.id')"
    if [[ -n "$MGMT_SP_ID" && "$MGMT_SP_ID" != "null" ]]; then
        _ENTRA_ROLLBACK_STACK+=("az ad sp delete --id ${MGMT_SP_ID}")
    fi
    print_success "Service principal created."

    # ---- Grant admin consent ----
    print_status "Granting admin consent for management app permissions..."
    if ! az ad app permission admin-consent --id "${MGMT_APP_ID}" >/dev/null 2>&1; then
        print_warning "Admin consent may require Global Administrator privileges."
        print_warning "You can grant consent later in the Azure Portal."
    else
        print_success "Admin consent granted."
    fi

    # ---- Store credentials securely ----
    print_status "Storing management app credentials..."

    if command -v op >/dev/null 2>&1 && [[ -n "$vault" ]] && op whoami >/dev/null 2>&1; then
        # Store in 1Password
        print_status "Saving credentials to 1Password vault: ${vault}..."
        if op item create \
            --category "API Credential" \
            --title "netbird-${project_name}-mgmt" \
            --vault "${vault}" \
            "username=${MGMT_APP_ID}" \
            "credential=${CLIENT_SECRET}" >/dev/null 2>&1; then
            print_success "Credentials saved to 1Password."
        else
            print_warning "Failed to save to 1Password. Falling back to local file."
            _entra_save_creds_to_file "${project_name}" "${MGMT_APP_ID}" "${CLIENT_SECRET}" "${MGMT_OBJECT_ID}"
        fi
    else
        # Fallback: save to local file
        if [[ -n "$vault" ]]; then
            print_warning "1Password CLI not available or not authenticated. Saving credentials locally."
        fi
        _entra_save_creds_to_file "${project_name}" "${MGMT_APP_ID}" "${CLIENT_SECRET}" "${MGMT_OBJECT_ID}"
    fi

    # ---- Store results in exported variables ----
    ENTRA_MGMT_CLIENT_ID="${MGMT_APP_ID}"
    ENTRA_MGMT_OBJECT_ID="${MGMT_OBJECT_ID}"
    ENTRA_MGMT_CLIENT_SECRET="${CLIENT_SECRET}"

    echo ""
    print_success "Management app registration complete."
    print_highlight "  Client ID (App ID): ${ENTRA_MGMT_CLIENT_ID}"
    print_highlight "  Object ID:          ${ENTRA_MGMT_OBJECT_ID}"
    print_highlight "  Secret:             ********** (stored securely)"
    echo ""

    return 0
}

# Helper: save management credentials to local file
_entra_save_creds_to_file() {
    local project_name="$1"
    local client_id="$2"
    local client_secret="$3"
    local object_id="$4"

    mkdir -p "${ENTRA_CREDS_DIR}"
    chmod 0700 "${ENTRA_CREDS_DIR}"

    local creds_file="${ENTRA_CREDS_DIR}/${project_name}.env"

    cat > "${creds_file}" <<CREDS_EOF
MGMT_CLIENT_ID=${client_id}
MGMT_CLIENT_SECRET=${client_secret}
MGMT_OBJECT_ID=${object_id}
CREDS_EOF

    chmod 0600 "${creds_file}"
    print_success "Credentials saved to: ${creds_file}"
    print_warning "This file contains secrets. Ensure it is in .gitignore."
}

###############################################################################
# 5. entra_verify_setup
#    Verifies all Entra ID registrations are correct
###############################################################################

entra_verify_setup() {
    print_header "Verifying Entra ID Setup..."
    echo ""

    local errors=0

    # ---- Verify SPA app exists ----
    print_status "Checking SPA app registration..."
    if [[ -z "$ENTRA_SPA_CLIENT_ID" ]]; then
        print_error "SPA Client ID is not set."
        (( errors++ ))
    else
        local spa_app
        spa_app="$(az ad app show --id "${ENTRA_SPA_CLIENT_ID}" 2>/dev/null)"
        if [[ $? -ne 0 || -z "$spa_app" ]]; then
            print_error "SPA app not found in Entra ID: ${ENTRA_SPA_CLIENT_ID}"
            (( errors++ ))
        else
            print_success "SPA app exists: ${ENTRA_SPA_CLIENT_ID}"

            # ---- Verify redirect URIs ----
            print_status "Checking SPA redirect URIs..."
            local spa_redirects
            spa_redirects="$(echo "${spa_app}" | jq -r '.spa.redirectUris[]?' 2>/dev/null)"
            if echo "${spa_redirects}" | grep -q "/auth" && echo "${spa_redirects}" | grep -q "/silent-auth"; then
                print_success "SPA redirect URIs are configured correctly."
            else
                print_warning "SPA redirect URIs may not be configured correctly."
                print_status "Expected /auth and /silent-auth redirect URIs."
                (( errors++ ))
            fi

            # ---- Verify permissions ----
            print_status "Checking API permissions..."
            local perm_count
            perm_count="$(echo "${spa_app}" | jq '[.requiredResourceAccess[]?.resourceAccess[]?] | length' 2>/dev/null)"
            if [[ "$perm_count" -ge 6 ]]; then
                print_success "API permissions are configured (${perm_count} permissions found)."
            else
                print_warning "Expected at least 6 API permissions, found ${perm_count:-0}."
                (( errors++ ))
            fi

            # ---- Verify service principal ----
            print_status "Checking SPA service principal..."
            if az ad sp show --id "${ENTRA_SPA_CLIENT_ID}" >/dev/null 2>&1; then
                print_success "SPA service principal exists."
            else
                print_error "SPA service principal not found."
                (( errors++ ))
            fi
        fi
    fi

    echo ""

    # ---- Verify management app exists ----
    print_status "Checking management app registration..."
    if [[ -z "$ENTRA_MGMT_CLIENT_ID" ]]; then
        print_error "Management Client ID is not set."
        (( errors++ ))
    else
        local mgmt_app
        mgmt_app="$(az ad app show --id "${ENTRA_MGMT_CLIENT_ID}" 2>/dev/null)"
        if [[ $? -ne 0 || -z "$mgmt_app" ]]; then
            print_error "Management app not found in Entra ID: ${ENTRA_MGMT_CLIENT_ID}"
            (( errors++ ))
        else
            print_success "Management app exists: ${ENTRA_MGMT_CLIENT_ID}"

            # Verify management service principal
            print_status "Checking management service principal..."
            if az ad sp show --id "${ENTRA_MGMT_CLIENT_ID}" >/dev/null 2>&1; then
                print_success "Management service principal exists."
            else
                print_error "Management service principal not found."
                (( errors++ ))
            fi
        fi
    fi

    echo ""

    # ---- Print summary table ----
    print_divider
    print_header "  Entra ID Configuration Summary"
    print_divider
    echo ""
    echo "  Tenant ID:              ${ENTRA_TENANT_ID:-<not set>}"
    echo "  SPA Client ID:          ${ENTRA_SPA_CLIENT_ID:-<not set>}"
    echo "  SPA Object ID:          ${ENTRA_SPA_OBJECT_ID:-<not set>}"
    echo "  Management Client ID:   ${ENTRA_MGMT_CLIENT_ID:-<not set>}"
    echo "  Management Object ID:   ${ENTRA_MGMT_OBJECT_ID:-<not set>}"
    echo "  Management Secret:      ${ENTRA_MGMT_CLIENT_SECRET:+**********}"
    echo ""
    print_divider

    if [[ "$errors" -gt 0 ]]; then
        echo ""
        print_error "Verification found ${errors} issue(s). Review the output above."
        return 1
    fi

    echo ""
    print_success "All Entra ID checks passed."
    return 0
}

###############################################################################
# 6. entra_full_setup(domain, project_name, [vault])
#    Orchestrator: login -> create SPA -> create management -> verify
###############################################################################

entra_full_setup() {
    local domain="$1"
    local project_name="$2"
    local vault="${3:-}"

    if [[ -z "$domain" || -z "$project_name" ]]; then
        print_error "Usage: entra_full_setup <domain> <project_name> [vault]"
        return 1
    fi

    # Reset rollback stack for this run
    _ENTRA_ROLLBACK_STACK=()

    print_divider
    print_header "  Netbird Entra ID Automatic Setup"
    print_divider
    echo ""
    print_status "Domain:       ${domain}"
    print_status "Project:      ${project_name}"
    if [[ -n "$vault" ]]; then
        print_status "1Password:    vault '${vault}'"
    fi
    echo ""

    # Step 1: Login
    print_header "Step 1/4: Azure Authentication"
    if ! entra_login; then
        print_error "Azure login failed. Aborting setup."
        _entra_rollback
        return 1
    fi
    echo ""

    # Step 2: Create SPA app
    print_header "Step 2/4: SPA App Registration"
    if ! entra_create_spa_app "${domain}" "${project_name}"; then
        print_error "SPA app creation failed. Rolling back..."
        _entra_rollback
        return 1
    fi
    echo ""

    # Step 3: Create management app
    print_header "Step 3/4: Management App Registration"
    if ! entra_create_management_app "${project_name}" "${vault}"; then
        print_error "Management app creation failed. Rolling back..."
        _entra_rollback
        return 1
    fi
    echo ""

    # Step 4: Verify
    print_header "Step 4/4: Verification"
    if ! entra_verify_setup; then
        print_warning "Verification reported issues but apps were created."
        print_status "You may need to grant admin consent manually in the Azure Portal."
    fi
    echo ""

    # Clear rollback stack on success (no cleanup needed)
    _ENTRA_ROLLBACK_STACK=()

    print_divider
    print_header "  Entra ID Setup Complete"
    print_divider
    echo ""
    print_success "All Entra ID app registrations are ready for Netbird."
    echo ""

    return 0
}

###############################################################################
# 7. entra_interactive_or_manual(domain, project_name, [vault])
#    Main entry point for deploy scripts. Returns 1 for manual flow.
###############################################################################

entra_interactive_or_manual() {
    local domain="$1"
    local project_name="$2"
    local vault="${3:-}"

    if [[ -z "$domain" || -z "$project_name" ]]; then
        print_error "Usage: entra_interactive_or_manual <domain> <project_name> [vault]"
        return 1
    fi

    echo ""
    print_divider
    print_header "  Entra ID Configuration"
    print_divider
    echo ""

    # Check if Azure CLI is available before showing the menu
    if ! command -v az >/dev/null 2>&1; then
        print_warning "Azure CLI not found, falling back to manual setup."
        print_status "Install Azure CLI for automatic setup: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        echo ""
        return 1
    fi

    echo "  [1] Automatic setup (recommended) - requires Azure CLI"
    echo "  [2] Manual setup - follow portal instructions"
    echo ""

    local choice
    read -rp "Select option [1/2]: " choice

    case "$choice" in
        1)
            echo ""
            print_status "Starting automatic Entra ID setup..."
            echo ""

            # Verify az CLI readiness
            local az_status
            entra_check_az_cli
            az_status=$?

            if [[ "$az_status" -eq 1 ]]; then
                print_error "Azure CLI is required for automatic setup."
                return 1
            fi

            # If not logged in, the full_setup will handle login
            if ! entra_full_setup "${domain}" "${project_name}" "${vault}"; then
                print_error "Automatic Entra ID setup failed."
                if read_yes_no "Would you like to try manual setup instead?" "y"; then
                    return 1
                fi
                return 1
            fi

            return 0
            ;;
        2)
            print_status "Manual setup selected. The deploy script will provide portal instructions."
            echo ""
            return 1
            ;;
        *)
            print_warning "Invalid selection. Defaulting to manual setup."
            echo ""
            return 1
            ;;
    esac
}
