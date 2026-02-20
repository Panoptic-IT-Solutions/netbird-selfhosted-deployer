#!/usr/bin/env bash
# hcloud-helpers.sh - Idempotent Hetzner Cloud resource management helpers
# Provides functions to create/verify firewalls, servers, and SSH keys
# with safe, idempotent behavior (won't duplicate existing resources).

# Source guard - prevent double-sourcing
[[ -n "${_HCLOUD_HELPERS_LOADED:-}" ]] && return 0; _HCLOUD_HELPERS_LOADED=1

# Source shared output helpers
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/output-helpers.sh"

# ---------------------------------------------------------------------------
# ensure_firewall - Create or verify a Hetzner Cloud firewall
#
# Arguments:
#   $1 - name:       Firewall name
#   $2 - rules_json: JSON string containing firewall rules
#
# Returns 0 on success. If the firewall exists with different rules, the user
# is prompted whether to update them.
# ---------------------------------------------------------------------------
ensure_firewall() {
    local name="$1"
    local rules_json="$2"

    if [[ -z "$name" || -z "$rules_json" ]]; then
        print_error "Usage: ensure_firewall <name> <rules_json>"
        return 1
    fi

    local existing_json
    existing_json=$(hcloud firewall describe "$name" -o json 2>/dev/null)

    if [[ $? -eq 0 && -n "$existing_json" ]]; then
        # Firewall exists - compare rules
        local current_rules
        current_rules=$(echo "$existing_json" | jq -S '.rules // []')
        local desired_rules
        desired_rules=$(echo "$rules_json" | jq -S '.')

        if [[ "$current_rules" == "$desired_rules" ]]; then
            print_success "Firewall '$name' already exists with correct rules"
            return 0
        else
            print_warning "Firewall '$name' exists but rules differ:"
            echo ""
            diff <(echo "$current_rules") <(echo "$desired_rules") || true
            echo ""

            if read_yes_no "Update firewall '$name' with new rules?" "n"; then
                # Remove all existing rules first
                local rule_count
                rule_count=$(echo "$current_rules" | jq 'length')
                local i
                for (( i = rule_count - 1; i >= 0; i-- )); do
                    local direction
                    direction=$(echo "$current_rules" | jq -r ".[$i].direction")
                    local protocol
                    protocol=$(echo "$current_rules" | jq -r ".[$i].protocol")
                    local port
                    port=$(echo "$current_rules" | jq -r ".[$i].port // empty")
                    local source_ips
                    source_ips=$(echo "$current_rules" | jq -r ".[$i].source_ips[]? // empty" | paste -sd, -)

                    local delete_args=("--direction" "$direction" "--protocol" "$protocol")
                    [[ -n "$port" ]] && delete_args+=("--port" "$port")
                    [[ -n "$source_ips" ]] && delete_args+=("--source-ips" "$source_ips")

                    hcloud firewall delete-rule "$name" "${delete_args[@]}" 2>/dev/null || true
                done

                # Apply new rules
                local new_rule_count
                new_rule_count=$(echo "$rules_json" | jq 'length')
                for (( i = 0; i < new_rule_count; i++ )); do
                    local direction
                    direction=$(echo "$rules_json" | jq -r ".[$i].direction")
                    local protocol
                    protocol=$(echo "$rules_json" | jq -r ".[$i].protocol")
                    local port
                    port=$(echo "$rules_json" | jq -r ".[$i].port // empty")
                    local source_ips
                    source_ips=$(echo "$rules_json" | jq -r ".[$i].source_ips[]? // empty" | paste -sd, -)
                    local dest_ips
                    dest_ips=$(echo "$rules_json" | jq -r ".[$i].destination_ips[]? // empty" | paste -sd, -)

                    local add_args=("--direction" "$direction" "--protocol" "$protocol")
                    [[ -n "$port" ]] && add_args+=("--port" "$port")
                    [[ -n "$source_ips" ]] && add_args+=("--source-ips" "$source_ips")
                    [[ -n "$dest_ips" ]] && add_args+=("--destination-ips" "$dest_ips")

                    hcloud firewall add-rule "$name" "${add_args[@]}"
                done

                print_success "Firewall '$name' updated with new rules"
            else
                print_status "Keeping existing firewall '$name' unchanged"
            fi
            return 0
        fi
    fi

    # Firewall does not exist - create it
    print_status "Creating firewall '$name'..."
    hcloud firewall create --name "$name"

    local rule_count
    rule_count=$(echo "$rules_json" | jq 'length')
    local i
    for (( i = 0; i < rule_count; i++ )); do
        local direction
        direction=$(echo "$rules_json" | jq -r ".[$i].direction")
        local protocol
        protocol=$(echo "$rules_json" | jq -r ".[$i].protocol")
        local port
        port=$(echo "$rules_json" | jq -r ".[$i].port // empty")
        local source_ips
        source_ips=$(echo "$rules_json" | jq -r ".[$i].source_ips[]? // empty" | paste -sd, -)
        local dest_ips
        dest_ips=$(echo "$rules_json" | jq -r ".[$i].destination_ips[]? // empty" | paste -sd, -)

        local add_args=("--direction" "$direction" "--protocol" "$protocol")
        [[ -n "$port" ]] && add_args+=("--port" "$port")
        [[ -n "$source_ips" ]] && add_args+=("--source-ips" "$source_ips")
        [[ -n "$dest_ips" ]] && add_args+=("--destination-ips" "$dest_ips")

        print_status "  Adding rule: $direction $protocol ${port:+port $port}"
        hcloud firewall add-rule "$name" "${add_args[@]}"
    done

    print_success "Firewall '$name' created with $rule_count rule(s)"
    return 0
}

# ---------------------------------------------------------------------------
# ensure_server - Create or reuse a Hetzner Cloud server
#
# Arguments:
#   $1 - name:        Server name
#   $2 - server_type: e.g. cx11, cpx11, cx21
#   $3 - image:       e.g. ubuntu-22.04
#   $4 - location:    e.g. nbg1, fsn1, hel1
#   $5 - ssh_keys:    Comma-separated SSH key names
#   $6 - firewall:    (optional) Firewall name to attach
#   $7 - labels:      (optional) Comma-separated key=value labels
#
# Sets global variables:
#   SERVER_IP - Public IPv4 address of the server
#   SERVER_ID - Hetzner Cloud server ID
# ---------------------------------------------------------------------------
ensure_server() {
    local name="$1"
    local server_type="$2"
    local image="$3"
    local location="$4"
    local ssh_keys="$5"
    local firewall="${6:-}"
    local labels="${7:-}"

    if [[ -z "$name" || -z "$server_type" || -z "$image" || -z "$location" || -z "$ssh_keys" ]]; then
        print_error "Usage: ensure_server <name> <type> <image> <location> <ssh_keys> [firewall] [labels]"
        return 1
    fi

    local existing_json
    existing_json=$(hcloud server describe "$name" -o json 2>/dev/null)

    if [[ $? -eq 0 && -n "$existing_json" ]]; then
        # Server already exists
        local existing_ip
        existing_ip=$(echo "$existing_json" | jq -r '.public_net.ipv4.ip')
        local existing_status
        existing_status=$(echo "$existing_json" | jq -r '.status')
        local existing_id
        existing_id=$(echo "$existing_json" | jq -r '.id')

        print_warning "Server '$name' already exists (IP: $existing_ip, Status: $existing_status)"

        if read_yes_no "Reuse existing server?" "y"; then
            SERVER_IP="$existing_ip"
            SERVER_ID="$existing_id"
            print_success "Reusing server '$name' at $SERVER_IP"
            return 0
        else
            print_status "Please choose a different server name and try again."
            return 1
        fi
    fi

    # Server does not exist - create it
    print_status "Creating server '$name' (type=$server_type, image=$image, location=$location)..."

    local cmd=("hcloud" "server" "create"
        "--name" "$name"
        "--type" "$server_type"
        "--image" "$image"
        "--location" "$location"
    )

    # Add SSH keys (split on comma)
    local key
    IFS=',' read -ra key_array <<< "$ssh_keys"
    for key in "${key_array[@]}"; do
        cmd+=("--ssh-key" "$(echo "$key" | xargs)")  # xargs trims whitespace
    done

    # Add firewall if specified
    if [[ -n "$firewall" ]]; then
        cmd+=("--firewall" "$firewall")
    fi

    # Add labels if specified
    if [[ -n "$labels" ]]; then
        local label
        IFS=',' read -ra label_array <<< "$labels"
        for label in "${label_array[@]}"; do
            cmd+=("--label" "$(echo "$label" | xargs)")
        done
    fi

    # Execute server creation
    local create_output
    create_output=$("${cmd[@]}" 2>&1)
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create server '$name': $create_output"
        return 1
    fi

    echo "$create_output"

    # Extract the IP and ID from the newly created server
    local server_json
    server_json=$(hcloud server describe "$name" -o json 2>/dev/null)
    SERVER_IP=$(echo "$server_json" | jq -r '.public_net.ipv4.ip')
    SERVER_ID=$(echo "$server_json" | jq -r '.id')

    print_success "Server '$name' created (IP: $SERVER_IP, ID: $SERVER_ID)"
    return 0
}

# ---------------------------------------------------------------------------
# ensure_ssh_key_hcloud - Register an SSH key with Hetzner Cloud
#
# Arguments:
#   $1 - name:                    Name for the SSH key in hcloud
#   $2 - public_key_file_or_str:  Path to a .pub file or the public key string
#
# Sets global variable:
#   HCLOUD_SSH_KEY_NAME - The name of the registered SSH key
# ---------------------------------------------------------------------------
ensure_ssh_key_hcloud() {
    local name="$1"
    local public_key_file_or_string="$2"

    if [[ -z "$name" || -z "$public_key_file_or_string" ]]; then
        print_error "Usage: ensure_ssh_key_hcloud <name> <public_key_file_or_string>"
        return 1
    fi

    # Resolve the public key content
    local public_key
    if [[ -f "$public_key_file_or_string" ]]; then
        public_key=$(cat "$public_key_file_or_string")
    else
        public_key="$public_key_file_or_string"
    fi

    # Compute the fingerprint of the provided key
    local provided_fingerprint
    if [[ -f "$public_key_file_or_string" ]]; then
        provided_fingerprint=$(ssh-keygen -lf "$public_key_file_or_string" -E md5 2>/dev/null | awk '{print $2}' | sed 's/^MD5://')
    else
        provided_fingerprint=$(echo "$public_key" | ssh-keygen -lf /dev/stdin -E md5 2>/dev/null | awk '{print $2}' | sed 's/^MD5://')
    fi

    # Check if the key already exists by name
    local existing_json
    existing_json=$(hcloud ssh-key describe "$name" -o json 2>/dev/null)

    if [[ $? -eq 0 && -n "$existing_json" ]]; then
        # Key exists - verify fingerprint matches
        local existing_fingerprint
        existing_fingerprint=$(echo "$existing_json" | jq -r '.fingerprint')

        if [[ "$existing_fingerprint" == "$provided_fingerprint" ]]; then
            print_success "SSH key '$name' already registered with matching fingerprint"
            HCLOUD_SSH_KEY_NAME="$name"
            return 0
        else
            print_warning "SSH key '$name' exists but fingerprint does not match!"
            print_warning "  Existing:  $existing_fingerprint"
            print_warning "  Provided:  $provided_fingerprint"
            print_error "Cannot overwrite SSH key with different fingerprint. Use a different name."
            return 1
        fi
    fi

    # Key does not exist - create it
    print_status "Registering SSH key '$name' with Hetzner Cloud..."

    if [[ -f "$public_key_file_or_string" ]]; then
        hcloud ssh-key create --name "$name" --public-key-from-file "$public_key_file_or_string"
    else
        hcloud ssh-key create --name "$name" --public-key "$public_key"
    fi

    if [[ $? -ne 0 ]]; then
        print_error "Failed to register SSH key '$name'"
        return 1
    fi

    HCLOUD_SSH_KEY_NAME="$name"
    print_success "SSH key '$name' registered successfully"
    return 0
}

# ---------------------------------------------------------------------------
# wait_for_server_ready - Poll SSH connectivity until the server is reachable
#
# Arguments:
#   $1 - server_ip: IP address to connect to
#   $2 - timeout:   (optional) Max seconds to wait, default 120
#
# Returns 0 when SSH is ready, 1 on timeout.
# ---------------------------------------------------------------------------
wait_for_server_ready() {
    local server_ip="$1"
    local timeout="${2:-120}"

    if [[ -z "$server_ip" ]]; then
        print_error "Usage: wait_for_server_ready <server_ip> [timeout]"
        return 1
    fi

    print_status "Waiting for server $server_ip to become ready (timeout: ${timeout}s)..."

    local elapsed=0
    local interval=5

    while [[ $elapsed -lt $timeout ]]; do
        if ssh -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=accept-new \
               -o BatchMode=yes \
               "root@${server_ip}" "echo ready" 2>/dev/null | grep -q "ready"; then
            echo ""
            print_success "Server $server_ip is ready (took ${elapsed}s)"
            return 0
        fi

        # Print a dot to show progress (no newline)
        printf "."
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo ""
    print_error "Timed out after ${timeout}s waiting for server $server_ip"
    return 1
}

# ---------------------------------------------------------------------------
# hcloud_context_ensure - Ensure an active hcloud CLI context is configured
#
# Checks for an active hcloud context and prompts the user to select or
# create one if none is active. Validates by listing servers.
# ---------------------------------------------------------------------------
hcloud_context_ensure() {
    # Check if hcloud CLI is installed
    if ! command_exists hcloud; then
        print_error "hcloud CLI is not installed. Please install it first."
        print_status "  See: https://github.com/hetznercloud/cli"
        return 1
    fi

    # Check for an active context
    local active_context
    active_context=$(hcloud context active 2>/dev/null)

    if [[ -n "$active_context" ]]; then
        print_status "Active hcloud context: $active_context"
    else
        print_warning "No active hcloud context found."

        # List available contexts
        local contexts
        contexts=$(hcloud context list 2>/dev/null)

        if [[ -n "$contexts" ]]; then
            print_status "Available contexts:"
            echo "$contexts"
            echo ""

            local context_name
            read -p "Enter context name to activate (or 'new' to create one): " -r context_name

            if [[ "$context_name" == "new" ]]; then
                local new_name
                read -p "Enter a name for the new context: " -r new_name
                local token
                read -sp "Enter your Hetzner Cloud API token: " -r token
                echo ""

                hcloud context create "$new_name"
                if [[ $? -ne 0 ]]; then
                    print_error "Failed to create context '$new_name'"
                    return 1
                fi
            else
                hcloud context use "$context_name"
                if [[ $? -ne 0 ]]; then
                    print_error "Failed to activate context '$context_name'"
                    return 1
                fi
            fi
        else
            # No contexts at all - create one
            print_status "No contexts exist. Let's create one."
            local new_name
            read -p "Enter a name for the new context: " -r new_name
            hcloud context create "$new_name"
            if [[ $? -ne 0 ]]; then
                print_error "Failed to create context '$new_name'"
                return 1
            fi
        fi
    fi

    # Validate the context by listing servers
    print_status "Validating hcloud context..."
    if hcloud server list >/dev/null 2>&1; then
        print_success "hcloud context is active and valid"
        return 0
    else
        print_error "hcloud context validation failed. Check your API token."
        return 1
    fi
}
