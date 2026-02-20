#!/usr/bin/env bash
# ssh-manager.sh - SSH key management with 1Password CLI integration and file-based fallback
# Source this file from deploy scripts or manage-ssh-keys.sh

# Prevent double-sourcing
[[ -n "${_SSH_MANAGER_LOADED:-}" ]] && return 0
_SSH_MANAGER_LOADED=1

# Source output helpers
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/output-helpers.sh"

# Project paths
PROJECT_ROOT="$(cd "${LIB_DIR}/.." && pwd)"
SSH_KEYS_DIR="${PROJECT_ROOT}/.ssh-keys"
SSH_KNOWN_HOSTS="${SSH_KEYS_DIR}/known_hosts"

# Exported variable for Hetzner key name (set by ssh_upload_key_to_hetzner)
SSH_HCLOUD_KEY_NAME=""

# Backend mode cache
SSH_BACKEND=""

###############################################################################
# Internal helpers
###############################################################################

# Detect whether 1Password CLI is available and authenticated
_ssh_mode() {
    if [[ -n "${SSH_BACKEND}" ]]; then
        echo "${SSH_BACKEND}"
        return 0
    fi

    if command_exists op && op whoami >/dev/null 2>&1; then
        SSH_BACKEND="1password"
    else
        SSH_BACKEND="file"
    fi

    echo "${SSH_BACKEND}"
}

# Internal SSH command helper used by all functions that SSH into servers
_ssh_cmd() {
    local target="$1"; shift
    ssh -F "${SSH_KEYS_DIR}/ssh-config" \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="${SSH_KNOWN_HOSTS}" \
        "$target" "$@"
}

###############################################################################
# 1. ssh_init_project_keys
###############################################################################
ssh_init_project_keys() {
    local project_name="${1:?project_name is required}"
    local vault="${2:-Netbird}"
    local mode
    mode="$(_ssh_mode)"

    print_status "Initialising SSH keys for project '${project_name}' (mode: ${mode})"

    if [[ "${mode}" == "1password" ]]; then
        # Check if item already exists in 1Password
        if op item get "netbird-${project_name}" --vault "${vault}" >/dev/null 2>&1; then
            print_success "1Password item 'netbird-${project_name}' already exists in vault '${vault}'"

            # Clean up local file-based keys if they exist
            if [[ -f "${SSH_KEYS_DIR}/${project_name}" ]]; then
                rm -f "${SSH_KEYS_DIR}/${project_name}" "${SSH_KEYS_DIR}/${project_name}.pub"
                print_status "Removed local key files (now managed by 1Password)"
            fi
            return 0
        fi

        # Migrate existing file-based keys to 1Password if they exist
        local key_path="${SSH_KEYS_DIR}/${project_name}"
        if [[ -f "${key_path}" ]]; then
            print_status "Found existing file-based SSH key. Migrating to 1Password..."

            local private_key
            private_key="$(cat "${key_path}")"

            # Ensure the vault exists
            if ! op vault get "${vault}" >/dev/null 2>&1; then
                print_status "Creating 1Password vault '${vault}'..."
                if ! op vault create "${vault}" >/dev/null 2>&1; then
                    print_error "Failed to create 1Password vault '${vault}'"
                    return 1
                fi
            fi

            # Import the existing private key into 1Password
            if op item create \
                    --category sshkey \
                    --title "netbird-${project_name}" \
                    --vault "${vault}" \
                    "private key=${private_key}" >/dev/null 2>&1; then
                print_success "Migrated SSH key to 1Password vault '${vault}'"

                # Remove local key files
                rm -f "${key_path}" "${key_path}.pub"
                print_status "Removed local key files"
                return 0
            else
                print_warning "Failed to migrate key to 1Password. Generating a new one instead."
            fi
        fi

        # Ensure the vault exists before creating a new key
        if ! op vault get "${vault}" >/dev/null 2>&1; then
            print_status "Creating 1Password vault '${vault}'..."
            if ! op vault create "${vault}" >/dev/null 2>&1; then
                print_error "Failed to create 1Password vault '${vault}'"
                return 1
            fi
        fi

        # Create SSH key item (1Password auto-generates Ed25519 key for sshkey category)
        if ! op item create \
                --category sshkey \
                --title "netbird-${project_name}" \
                --vault "${vault}" >/dev/null 2>&1; then
            print_error "Failed to create SSH key in 1Password vault '${vault}'"
            return 1
        fi

        print_success "Created SSH key 'netbird-${project_name}' in 1Password vault '${vault}'"
    else
        local key_path="${SSH_KEYS_DIR}/${project_name}"

        if [[ -f "${key_path}" ]]; then
            print_success "SSH key already exists at ${key_path}"
            return 0
        fi

        mkdir -p "${SSH_KEYS_DIR}"

        if ! ssh-keygen -t ed25519 -f "${key_path}" -N "" -C "netbird-${project_name}" >/dev/null 2>&1; then
            print_error "Failed to generate SSH key at ${key_path}"
            return 1
        fi

        chmod 600 "${key_path}"
        chmod 644 "${key_path}.pub"

        print_success "Generated Ed25519 SSH key at ${key_path} (file-based fallback)"
    fi

    return 0
}

###############################################################################
# 2. ssh_get_public_key
###############################################################################
ssh_get_public_key() {
    local project_name="${1:?project_name is required}"
    local vault="${2:-Netbird}"
    local mode
    mode="$(_ssh_mode)"

    if [[ "${mode}" == "1password" ]]; then
        local pubkey
        pubkey="$(op item get "netbird-${project_name}" --vault "${vault}" --fields "public key" 2>/dev/null)"
        if [[ -z "${pubkey}" ]]; then
            print_error "Failed to retrieve public key from 1Password for 'netbird-${project_name}'" >&2
            return 1
        fi
        echo "${pubkey}"
    else
        local pub_path="${SSH_KEYS_DIR}/${project_name}.pub"
        if [[ ! -f "${pub_path}" ]]; then
            print_error "Public key file not found: ${pub_path}" >&2
            return 1
        fi
        cat "${pub_path}"
    fi
}

###############################################################################
# 3. ssh_get_private_key_ref
###############################################################################
ssh_get_private_key_ref() {
    local project_name="${1:?project_name is required}"
    local vault="${2:-Netbird}"
    local mode
    mode="$(_ssh_mode)"

    if [[ "${mode}" == "1password" ]]; then
        echo "op://${vault}/netbird-${project_name}/private key"
    else
        local key_path="${SSH_KEYS_DIR}/${project_name}"
        if [[ ! -f "${key_path}" ]]; then
            print_error "Private key file not found: ${key_path}" >&2
            return 1
        fi
        echo "${key_path}"
    fi
}

###############################################################################
# 4. ssh_upload_key_to_hetzner
###############################################################################
ssh_upload_key_to_hetzner() {
    local project_name="${1:?project_name is required}"
    local vault="${2:-Netbird}"
    local pubkey
    local local_fingerprint
    local key_name="netbird-${project_name}"

    if ! command_exists hcloud; then
        print_error "hcloud CLI is not installed"
        return 1
    fi

    # Retrieve the public key
    pubkey="$(ssh_get_public_key "${project_name}" "${vault}")"
    if [[ -z "${pubkey}" ]]; then
        print_error "Could not retrieve public key for project '${project_name}'"
        return 1
    fi

    # Compute fingerprint of local key
    local_fingerprint="$(echo "${pubkey}" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}')"
    if [[ -z "${local_fingerprint}" ]]; then
        print_error "Failed to compute fingerprint for public key"
        return 1
    fi

    # Check if a key with this name or fingerprint already exists in Hetzner
    local existing_keys
    existing_keys="$(hcloud ssh-key list -o json 2>/dev/null)"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to list Hetzner SSH keys (check hcloud authentication)"
        return 1
    fi

    # Match by name first, then by fingerprint (hcloud uses MD5, ssh-keygen defaults to SHA256)
    local match_by_name
    match_by_name="$(echo "${existing_keys}" | jq -r --arg name "${key_name}" '.[] | select(.name == $name) | .name' 2>/dev/null)"

    if [[ -n "${match_by_name}" ]]; then
        # Key with this name exists — check if the public key matches
        local existing_pubkey
        existing_pubkey="$(echo "${existing_keys}" | jq -r --arg name "${key_name}" '.[] | select(.name == $name) | .public_key' 2>/dev/null)"

        if [[ "${existing_pubkey}" == "${pubkey}" ]]; then
            print_status "SSH key '${key_name}' already uploaded to Hetzner (fingerprint matches)"
            SSH_HCLOUD_KEY_NAME="${key_name}"
            return 0
        else
            # Name exists but key differs — delete and re-upload
            print_status "SSH key '${key_name}' exists in Hetzner but key has changed. Updating..."
            hcloud ssh-key delete "${key_name}" >/dev/null 2>&1
        fi
    fi

    # Upload the key
    if ! hcloud ssh-key create --name "${key_name}" --public-key "${pubkey}" >/dev/null 2>&1; then
        print_error "Failed to upload SSH key to Hetzner"
        return 1
    fi

    SSH_HCLOUD_KEY_NAME="${key_name}"
    print_success "Uploaded SSH key '${key_name}' to Hetzner (fingerprint: ${local_fingerprint})"
    return 0
}

###############################################################################
# 5. ssh_generate_config
###############################################################################
ssh_generate_config() {
    local server_name="${1:?server_name is required}"
    local ip="${2:?ip is required}"
    local project_name="${3:?project_name is required}"
    local vault="${4:-Netbird}"
    local mode
    mode="$(_ssh_mode)"

    local config_file="${SSH_KEYS_DIR}/ssh-config"

    mkdir -p "${SSH_KEYS_DIR}"
    touch "${config_file}"

    # Build the Host block
    local identity_line=""
    if [[ "${mode}" == "file" ]]; then
        identity_line="    IdentityFile ${SSH_KEYS_DIR}/${project_name}
    IdentitiesOnly yes"
    else
        # Point SSH to the 1Password agent socket
        # Export the public key so IdentitiesOnly can restrict SSH to just this key.
        # Without this, SSH tries ALL keys from the agent — if there are more than
        # MaxAuthTries (default 6), the server disconnects before the right key is tried.
        local pubkey_file="${SSH_KEYS_DIR}/${project_name}.pub"
        local pubkey
        pubkey="$(ssh_get_public_key "${project_name}" "${vault}" 2>/dev/null)" || true
        if [[ -n "${pubkey}" ]]; then
            echo "${pubkey}" > "${pubkey_file}"
            chmod 644 "${pubkey_file}"
            identity_line="    IdentityAgent \"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"
    IdentityFile ${pubkey_file}
    IdentitiesOnly yes"
        else
            identity_line="    IdentityAgent \"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
        fi
    fi

    local host_block
    host_block="Host ${server_name}
    HostName ${ip}
    User root
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ${SSH_KNOWN_HOSTS}
    LogLevel ERROR"

    if [[ -n "${identity_line}" ]]; then
        host_block="${host_block}
${identity_line}"
    fi

    # Check if entry already exists
    if grep -q "^Host ${server_name}$" "${config_file}" 2>/dev/null; then
        # Update the IP for the existing entry
        # Replace the HostName line within that block
        local tmp_file
        tmp_file="$(mktemp)"

        awk -v host="${server_name}" -v new_ip="${ip}" '
            /^Host / { current_host = $2 }
            current_host == host && /^[[:space:]]+HostName / {
                sub(/HostName .*/, "HostName " new_ip)
            }
            { print }
        ' "${config_file}" > "${tmp_file}"

        mv "${tmp_file}" "${config_file}"

        # Clear stale host key for this IP (server may have been recreated with a new key)
        ssh-keygen -R "$ip" -f "${SSH_KNOWN_HOSTS}" 2>/dev/null || true

        print_status "Updated IP for '${server_name}' to ${ip} in SSH config"
    else
        # Append a new block
        {
            # Add a blank line separator if the file is non-empty
            if [[ -s "${config_file}" ]]; then
                echo ""
            fi
            echo "${host_block}"
        } >> "${config_file}"
        print_success "Added SSH config entry for '${server_name}' (${ip})"
    fi

    chmod 600 "${config_file}"

    print_highlight "Connect with: ssh -F ${SSH_KEYS_DIR}/ssh-config ${server_name}"
    return 0
}

###############################################################################
# 6. ssh_configure_1p_agent
###############################################################################
ssh_configure_1p_agent() {
    local project_name="${1:?project_name is required}"
    local vault="${2:-Netbird}"
    local mode
    mode="$(_ssh_mode)"

    if [[ "${mode}" != "1password" ]]; then
        print_warning "ssh_configure_1p_agent requires 1Password mode (current mode: ${mode})"
        return 1
    fi

    local agent_toml="${HOME}/.config/1Password/ssh/agent.toml"

    # Ensure the directory exists
    mkdir -p "$(dirname "${agent_toml}")"
    touch "${agent_toml}"

    # Check if a block for this key already exists
    if grep -q "netbird-${project_name}" "${agent_toml}" 2>/dev/null; then
        print_status "1Password SSH agent already configured for 'netbird-${project_name}'"
        return 0
    fi

    # Append the ssh-keys block
    {
        # Add a blank line if file is non-empty
        if [[ -s "${agent_toml}" ]]; then
            echo ""
        fi
        echo '[[ssh-keys]]'
        echo "item = \"netbird-${project_name}\""
        echo "vault = \"${vault}\""
    } >> "${agent_toml}"

    print_success "Configured 1Password SSH agent for 'netbird-${project_name}' in vault '${vault}'"
    print_status "Agent config: ${agent_toml}"
    print_status "Ensure the 1Password SSH agent is enabled in 1Password Settings > Developer"
    return 0
}

###############################################################################
# 7. ssh_add_colleague_key
###############################################################################
ssh_add_colleague_key() {
    local server_alias_or_ip="${1:?server_alias_or_ip is required}"
    local pubkey_source="${2:?pubkey_source is required}"
    local pubkey
    local fingerprint
    local target

    # Resolve the public key from source
    if [[ "${pubkey_source}" == op://* ]]; then
        if ! command_exists op; then
            print_error "1Password CLI (op) is required to resolve op:// references"
            return 1
        fi
        pubkey="$(op read "${pubkey_source}" 2>/dev/null)"
        if [[ -z "${pubkey}" ]]; then
            print_error "Failed to read public key from 1Password: ${pubkey_source}"
            return 1
        fi
    else
        if [[ ! -f "${pubkey_source}" ]]; then
            print_error "Public key file not found: ${pubkey_source}"
            return 1
        fi
        pubkey="$(cat "${pubkey_source}")"
        if [[ -z "${pubkey}" ]]; then
            print_error "Public key file is empty: ${pubkey_source}"
            return 1
        fi
    fi

    # Compute fingerprint for display
    fingerprint="$(echo "${pubkey}" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}')"

    # Determine SSH target
    if [[ "${server_alias_or_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target="root@${server_alias_or_ip}"
    else
        target="${server_alias_or_ip}"
    fi

    # Check if key already exists on the server, then add if not
    local escaped_pubkey
    escaped_pubkey="$(echo "${pubkey}" | sed 's/[[\.*^$()+?{|]/\\&/g')"

    local remote_result
    remote_result="$(_ssh_cmd "${target}" bash -s <<REMOTE_SCRIPT
if grep -qF '${pubkey}' ~/.ssh/authorized_keys 2>/dev/null; then
    echo "EXISTS"
else
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo '${pubkey}' >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "ADDED"
fi
REMOTE_SCRIPT
)"

    if [[ $? -ne 0 ]]; then
        print_error "Failed to connect to '${server_alias_or_ip}'"
        return 1
    fi

    if [[ "${remote_result}" == "EXISTS" ]]; then
        print_status "Key already present on '${server_alias_or_ip}' (fingerprint: ${fingerprint})"
    elif [[ "${remote_result}" == "ADDED" ]]; then
        print_success "Added colleague key to '${server_alias_or_ip}' (fingerprint: ${fingerprint})"
    else
        print_error "Unexpected response from server: ${remote_result}"
        return 1
    fi

    return 0
}

###############################################################################
# 8. ssh_remove_colleague_key
###############################################################################
ssh_remove_colleague_key() {
    local server_alias_or_ip="${1:?server_alias_or_ip is required}"
    local fingerprint="${2:?fingerprint is required}"
    local target

    # Determine SSH target
    if [[ "${server_alias_or_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target="root@${server_alias_or_ip}"
    else
        target="${server_alias_or_ip}"
    fi

    # SSH in, find and remove the key matching the given fingerprint
    local remote_result
    remote_result="$(_ssh_cmd "${target}" bash -s -- "${fingerprint}" <<'REMOTE_SCRIPT'
TARGET_FP="$1"
AUTH_KEYS="$HOME/.ssh/authorized_keys"

if [[ ! -f "${AUTH_KEYS}" ]]; then
    echo "NO_FILE"
    exit 0
fi

TMPFILE="$(mktemp)"
FOUND=0

while IFS= read -r line; do
    # Skip empty lines
    [[ -z "${line}" ]] && continue
    # Compute fingerprint for this key
    LINE_FP="$(echo "${line}" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}')"
    if [[ "${LINE_FP}" == "${TARGET_FP}" ]]; then
        FOUND=1
        COMMENT="$(echo "${line}" | awk '{print $3}')"
        echo "REMOVED:${COMMENT}"
    else
        echo "${line}" >> "${TMPFILE}"
    fi
done < "${AUTH_KEYS}"

if [[ ${FOUND} -eq 1 ]]; then
    mv "${TMPFILE}" "${AUTH_KEYS}"
    chmod 600 "${AUTH_KEYS}"
else
    rm -f "${TMPFILE}"
    echo "NOT_FOUND"
fi
REMOTE_SCRIPT
)"

    if [[ $? -ne 0 ]]; then
        print_error "Failed to connect to '${server_alias_or_ip}'"
        return 1
    fi

    if [[ "${remote_result}" == "NO_FILE" ]]; then
        print_warning "No authorized_keys file found on '${server_alias_or_ip}'"
        return 1
    elif [[ "${remote_result}" == "NOT_FOUND" ]]; then
        print_warning "No key with fingerprint '${fingerprint}' found on '${server_alias_or_ip}'"
        return 1
    elif [[ "${remote_result}" == REMOVED:* ]]; then
        local comment="${remote_result#REMOVED:}"
        print_success "Removed key '${comment}' (fingerprint: ${fingerprint}) from '${server_alias_or_ip}'"
    else
        print_error "Unexpected response from server: ${remote_result}"
        return 1
    fi

    return 0
}

###############################################################################
# 9. ssh_list_authorized_keys
###############################################################################
ssh_list_authorized_keys() {
    local server_alias_or_ip="${1:?server_alias_or_ip is required}"
    local target

    # Determine SSH target
    if [[ "${server_alias_or_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target="root@${server_alias_or_ip}"
    else
        target="${server_alias_or_ip}"
    fi

    local remote_result
    remote_result="$(_ssh_cmd "${target}" bash -s <<'REMOTE_SCRIPT'
AUTH_KEYS="$HOME/.ssh/authorized_keys"

if [[ ! -f "${AUTH_KEYS}" ]]; then
    echo "NO_FILE"
    exit 0
fi

while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* ]] && continue
    INFO="$(echo "${line}" | ssh-keygen -lf /dev/stdin 2>/dev/null)"
    if [[ -n "${INFO}" ]]; then
        echo "${INFO}"
    fi
done < "${AUTH_KEYS}"
REMOTE_SCRIPT
)"

    if [[ $? -ne 0 ]]; then
        print_error "Failed to connect to '${server_alias_or_ip}'"
        return 1
    fi

    if [[ "${remote_result}" == "NO_FILE" ]]; then
        print_warning "No authorized_keys file found on '${server_alias_or_ip}'"
        return 0
    fi

    if [[ -z "${remote_result}" ]]; then
        print_status "No keys found in authorized_keys on '${server_alias_or_ip}'"
        return 0
    fi

    print_header "Authorized keys on '${server_alias_or_ip}':"
    print_divider
    printf "${BOLD}%-12s  %-50s  %s${NC}\n" "TYPE" "FINGERPRINT" "COMMENT"
    print_divider

    while IFS= read -r line; do
        local bits type_field fingerprint comment
        bits="$(echo "${line}" | awk '{print $1}')"
        fingerprint="$(echo "${line}" | awk '{print $2}')"
        comment="$(echo "${line}" | awk '{print $3}')"
        type_field="$(echo "${line}" | awk '{print $4}' | tr -d '()')"
        printf "%-12s  %-50s  %s\n" "${type_field}" "${fingerprint}" "${comment}"
    done <<< "${remote_result}"

    print_divider
    return 0
}

###############################################################################
# 10. ssh_setup_deploy_user
###############################################################################
ssh_setup_deploy_user() {
    local server_ip="${1:?server_ip is required}"
    local project_name="${2:?project_name is required}"
    local target

    # Always connect as root for initial setup
    if [[ "${server_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target="root@${server_ip}"
    else
        target="${server_ip}"
    fi

    print_status "Setting up deploy user on '${server_ip}'..."

    local remote_script
    read -r -d '' remote_script <<'REMOTE_SCRIPT' || true
set -euo pipefail

# Create deploy user if it doesn't exist
if ! id -u deploy >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo deploy
    echo "CREATED_USER"
else
    echo "USER_EXISTS"
fi

# Setup passwordless sudo
echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

# Copy SSH authorized_keys from root
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# Harden sshd configuration
SSHD_CONFIG="/etc/ssh/sshd_config"

# PermitRootLogin
if grep -q "^PermitRootLogin" "${SSHD_CONFIG}"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
elif grep -q "^#PermitRootLogin" "${SSHD_CONFIG}"; then
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
else
    echo "PermitRootLogin no" >> "${SSHD_CONFIG}"
fi

# PasswordAuthentication
if grep -q "^PasswordAuthentication" "${SSHD_CONFIG}"; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
elif grep -q "^#PasswordAuthentication" "${SSHD_CONFIG}"; then
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
else
    echo "PasswordAuthentication no" >> "${SSHD_CONFIG}"
fi

# MaxAuthTries
if grep -q "^MaxAuthTries" "${SSHD_CONFIG}"; then
    sed -i 's/^MaxAuthTries.*/MaxAuthTries 3/' "${SSHD_CONFIG}"
elif grep -q "^#MaxAuthTries" "${SSHD_CONFIG}"; then
    sed -i 's/^#MaxAuthTries.*/MaxAuthTries 3/' "${SSHD_CONFIG}"
else
    echo "MaxAuthTries 3" >> "${SSHD_CONFIG}"
fi

# Restart sshd
systemctl restart sshd

echo "HARDENED"
REMOTE_SCRIPT

    local remote_result
    remote_result="$(printf '%s' "${remote_script}" | _ssh_cmd "${target}" bash -s)"

    if [[ $? -ne 0 ]]; then
        print_error "Failed to set up deploy user on '${server_ip}'"
        return 1
    fi

    # Update SSH config to use deploy user for this server
    local config_file="${SSH_KEYS_DIR}/ssh-config"
    if [[ -f "${config_file}" ]]; then
        # Find the host block that matches this IP and change User to deploy
        local tmp_file
        tmp_file="$(mktemp)"
        local in_target_block=0

        while IFS= read -r line; do
            # Detect start of a Host block
            if [[ "${line}" =~ ^Host[[:space:]] ]]; then
                in_target_block=0
            fi

            # Check if the HostName in this block matches our server IP
            if [[ "${line}" =~ ^[[:space:]]+HostName[[:space:]]+${server_ip}$ ]]; then
                in_target_block=1
            fi

            # Replace User root with User deploy in the target block
            if [[ ${in_target_block} -eq 1 ]] && [[ "${line}" =~ ^[[:space:]]+User[[:space:]] ]]; then
                echo "    User deploy" >> "${tmp_file}"
            else
                echo "${line}" >> "${tmp_file}"
            fi
        done < "${config_file}"

        mv "${tmp_file}" "${config_file}"
        chmod 600 "${config_file}"
        print_status "Updated SSH config: User changed to 'deploy' for ${server_ip}"
    fi

    print_success "Deploy user setup complete on '${server_ip}'"
    print_divider
    print_warning "IMPORTANT: Test deploy user access BEFORE closing your current root session!"
    print_highlight "  ssh -F ${SSH_KEYS_DIR}/ssh-config <server-alias>"
    print_warning "Root login has been disabled. If deploy access fails, you may be locked out."
    print_divider
    return 0
}
