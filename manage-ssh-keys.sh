#!/usr/bin/env bash
# manage-ssh-keys.sh - Standalone CLI for SSH key management operations
# chmod +x manage-ssh-keys.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/ssh-manager.sh"

VERBOSE=0

###############################################################################
# Usage / Help
###############################################################################

usage() {
    cat <<'EOF'
Usage: manage-ssh-keys.sh <command> [options]

Commands:
  init <project> [--vault <vault>]       Generate SSH key (1Password or file-based)
  connect [--vault <vault>]              Connect to a colleague's NetBird server
  add <server-alias> <pubkey|op://ref>   Add a colleague's public key to a server
  remove <server-alias> <fingerprint>    Remove a key by fingerprint from a server
  list <server-alias>                    List all authorized keys on a server
  export-config                          Print the shareable SSH config
  setup-deploy-user <server-alias>       Create non-root deploy user on server
  agent-config [--vault <vault>]         Print 1Password agent.toml snippet

Options:
  -h, --help                             Show this help message
  -v, --verbose                          Enable verbose output

Examples:
  # Initialize SSH keys for a new project
  manage-ssh-keys.sh init acme-corp --vault Infrastructure

  # Add a colleague's key from a file
  manage-ssh-keys.sh add netbird-server /path/to/colleague.pub

  # Add a colleague's key from 1Password
  manage-ssh-keys.sh add netbird-server "op://Infrastructure/colleague-key/public key"

  # List all authorized keys on a server
  manage-ssh-keys.sh list netbird-server

  # Set up SSH access to a colleague's server (interactive)
  manage-ssh-keys.sh connect

  # Create deploy user (hardens SSH)
  manage-ssh-keys.sh setup-deploy-user netbird-server
EOF
}

###############################################################################
# Command: init
###############################################################################

cmd_init() {
    local project=""
    local vault="Netbird"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vault)
                if [[ $# -lt 2 ]]; then
                    print_error "--vault requires a value"
                    return 1
                fi
                vault="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option for init: $1"
                return 1
                ;;
            *)
                if [[ -z "${project}" ]]; then
                    project="$1"
                else
                    print_error "Unexpected argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "${project}" ]]; then
        print_error "Missing required argument: <project>"
        echo ""
        echo "Usage: manage-ssh-keys.sh init <project> [--vault <vault>]"
        return 1
    fi

    ssh_init_project_keys "${project}" "${vault}"

    # If 1Password mode, also configure the SSH agent
    local mode
    mode="$(_ssh_mode)"
    if [[ "${mode}" == "1password" ]]; then
        ssh_configure_1p_agent "${project}" "${vault}"
    fi

    # Print next steps
    echo ""
    print_divider
    print_header "Next steps:"
    echo ""
    if [[ "${mode}" == "1password" ]]; then
        print_status "1. Ensure the 1Password SSH agent is enabled in 1Password Settings > Developer"
        print_status "2. Run a deployment to generate SSH config for your servers"
        print_status "3. Share the public key with colleagues: op item get 'netbird-${project}' --vault '${vault}' --fields 'public key'"
    else
        print_status "1. Run a deployment to upload the key and generate SSH config"
        print_status "2. Share the public key with colleagues: cat ${SSH_KEYS_DIR}/${project}.pub"
        print_status "3. Add the private key to your SSH agent: ssh-add ${SSH_KEYS_DIR}/${project}"
    fi
    print_divider
}

###############################################################################
# Command: connect
###############################################################################

cmd_connect() {
    local vault="Netbird"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vault)
                if [[ $# -lt 2 ]]; then
                    print_error "--vault requires a value"
                    return 1
                fi
                vault="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option for connect: $1"
                return 1
                ;;
            *)
                print_error "Unexpected argument: $1"
                return 1
                ;;
        esac
    done

    # Check prerequisites
    if ! command_exists hcloud; then
        print_error "hcloud CLI is not installed."
        print_status "Install: https://github.com/hetznercloud/cli"
        return 1
    fi

    if ! hcloud server list >/dev/null 2>&1; then
        print_error "hcloud is not authenticated. Run: hcloud context create <project>"
        return 1
    fi

    if ! command_exists op; then
        print_error "1Password CLI (op) is not installed."
        print_status "Install: https://developer.1password.com/docs/cli/get-started/"
        return 1
    fi

    if ! op whoami >/dev/null 2>&1; then
        print_error "1Password CLI is not authenticated. Run: op signin"
        return 1
    fi

    # List NetBird servers from Hetzner
    local servers_json
    servers_json="$(hcloud server list -l managed-by=netbird-selfhosted -o json 2>/dev/null)"

    if [[ -z "${servers_json}" || "${servers_json}" == "[]" ]]; then
        print_error "No NetBird servers found (label: managed-by=netbird-selfhosted)"
        return 1
    fi

    # Parse into arrays
    local names=() ips=() statuses=()
    while IFS= read -r name; do names+=("${name}"); done < <(echo "${servers_json}" | jq -r '.[].name')
    while IFS= read -r ip; do ips+=("${ip}"); done < <(echo "${servers_json}" | jq -r '.[].public_net.ipv4.ip')
    while IFS= read -r status; do statuses+=("${status}"); done < <(echo "${servers_json}" | jq -r '.[].status')

    local count=${#names[@]}

    if [[ ${count} -eq 0 ]]; then
        print_error "No NetBird servers found"
        return 1
    fi

    local selection=0

    if [[ ${count} -eq 1 ]]; then
        print_status "Auto-selecting the only server: ${names[0]}"
        selection=0
    else
        # Show numbered menu
        print_header "Available NetBird servers:"
        print_divider
        printf "${BOLD}  %-4s %-35s %-18s %s${NC}\n" "#" "NAME" "IP" "STATUS"
        print_divider
        for i in "${!names[@]}"; do
            printf "  %-4s %-35s %-18s %s\n" "$((i + 1))" "${names[$i]}" "${ips[$i]}" "${statuses[$i]}"
        done
        print_divider

        local choice
        while true; do
            read -p "Select a server [1-${count}]: " -r choice
            if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
                selection=$((choice - 1))
                break
            fi
            print_warning "Invalid selection. Enter a number between 1 and ${count}."
        done
    fi

    local server_name="${names[$selection]}"
    local server_ip="${ips[$selection]}"

    # Derive project name by stripping the "netbird-selfhosted-" prefix
    local project_name="${server_name#netbird-selfhosted-}"

    print_status "Server: ${server_name} (${server_ip})"
    print_status "Project: ${project_name}"

    # Verify the SSH key exists in 1Password
    if ! op item get "netbird-${project_name}" --vault "${vault}" >/dev/null 2>&1; then
        print_error "1Password item 'netbird-${project_name}' not found in vault '${vault}'"
        print_status "Ask the server owner to share the vault, or specify a different vault with --vault"
        return 1
    fi

    print_success "Found SSH key 'netbird-${project_name}' in vault '${vault}'"

    # Configure 1Password SSH agent
    ssh_configure_1p_agent "${project_name}" "${vault}"

    # Generate SSH config entry
    ssh_generate_config "${server_name}" "${server_ip}" "${project_name}" "${vault}"

    # Print ready-to-use command
    echo ""
    print_divider
    print_header "Ready! Connect with:"
    echo ""
    print_highlight "  ssh -F ${SSH_KEYS_DIR}/ssh-config ${server_name}"
    echo ""
    print_divider
}

###############################################################################
# Command: add
###############################################################################

cmd_add() {
    if [[ $# -lt 2 ]]; then
        print_error "Missing required arguments"
        echo ""
        echo "Usage: manage-ssh-keys.sh add <server-alias> <pubkey|op://ref>"
        echo ""
        echo "  <server-alias>     Server alias from SSH config (or IP address)"
        echo "  <pubkey|op://ref>  Path to public key file or 1Password reference"
        return 1
    fi

    local server="$1"
    local pubkey_source="$2"

    ssh_add_colleague_key "${server}" "${pubkey_source}"
}

###############################################################################
# Command: remove
###############################################################################

cmd_remove() {
    if [[ $# -lt 2 ]]; then
        print_error "Missing required arguments"
        echo ""
        echo "Usage: manage-ssh-keys.sh remove <server-alias> <fingerprint>"
        echo ""
        echo "  <server-alias>  Server alias from SSH config (or IP address)"
        echo "  <fingerprint>   SSH key fingerprint (e.g., SHA256:abc123...)"
        return 1
    fi

    local server="$1"
    local fingerprint="$2"

    ssh_remove_colleague_key "${server}" "${fingerprint}"
}

###############################################################################
# Command: list
###############################################################################

cmd_list() {
    if [[ $# -lt 1 ]]; then
        print_error "Missing required argument: <server-alias>"
        echo ""
        echo "Usage: manage-ssh-keys.sh list <server-alias>"
        return 1
    fi

    local server="$1"

    ssh_list_authorized_keys "${server}"
}

###############################################################################
# Command: export-config
###############################################################################

cmd_export_config() {
    local config_file="${PROJECT_ROOT}/.ssh-keys/ssh-config"

    if [[ -f "${config_file}" ]]; then
        print_header "SSH config (${config_file}):"
        print_divider
        echo ""
        echo "# Add to ~/.ssh/config or use with: ssh -F ${config_file} <server-alias>"
        echo "# ---"
        cat "${config_file}"
        echo ""
        print_divider
        print_status "To use this config directly:"
        print_highlight "  ssh -F ${config_file} <server-alias>"
        echo ""
        print_status "Or include in your ~/.ssh/config:"
        print_highlight "  echo 'Include ${config_file}' >> ~/.ssh/config"
    else
        print_warning "No SSH config generated yet. Run a deployment first."
    fi
}

###############################################################################
# Command: setup-deploy-user
###############################################################################

cmd_setup_deploy_user() {
    if [[ $# -lt 1 ]]; then
        print_error "Missing required argument: <server-alias>"
        echo ""
        echo "Usage: manage-ssh-keys.sh setup-deploy-user <server-alias>"
        return 1
    fi

    local server="$1"

    # Warn the user about what this does
    print_divider
    print_warning "This command will:"
    echo "  - Create a non-root 'deploy' user with sudo privileges"
    echo "  - Copy current root SSH keys to the deploy user"
    echo "  - Disable root SSH login"
    echo "  - Disable password authentication"
    echo "  - Set MaxAuthTries to 3"
    echo ""
    print_warning "After this, you will NO LONGER be able to SSH in as root."
    print_divider
    echo ""

    if ! read_yes_no "Are you sure you want to proceed?"; then
        print_status "Aborted."
        return 0
    fi

    echo ""

    # Resolve IP from ssh-config if it is an alias
    local server_ip="${server}"
    local config_file="${PROJECT_ROOT}/.ssh-keys/ssh-config"

    if [[ -f "${config_file}" ]] && ! [[ "${server}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local resolved_ip
        resolved_ip="$(awk -v host="${server}" '
            /^Host / { current_host = $2 }
            current_host == host && /^[[:space:]]+HostName / { print $2; exit }
        ' "${config_file}")"

        if [[ -n "${resolved_ip}" ]]; then
            server_ip="${resolved_ip}"
            print_status "Resolved '${server}' to ${server_ip}"
        fi
    fi

    # Derive project name from the server alias or use a generic name
    local project_name
    project_name="$(basename "${server}")"

    ssh_setup_deploy_user "${server_ip}" "${project_name}"
}

###############################################################################
# Command: agent-config
###############################################################################

cmd_agent_config() {
    local vault="Netbird"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vault)
                if [[ $# -lt 2 ]]; then
                    print_error "--vault requires a value"
                    return 1
                fi
                vault="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option for agent-config: $1"
                return 1
                ;;
            *)
                print_error "Unexpected argument: $1"
                return 1
                ;;
        esac
    done

    # Check if 1Password mode is active
    local mode
    mode="$(_ssh_mode)"

    if [[ "${mode}" != "1password" ]]; then
        print_error "1Password CLI is not available or not authenticated."
        echo ""
        print_status "The agent-config command requires 1Password CLI (op) to be installed and signed in."
        print_status "Install: https://developer.1password.com/docs/cli/get-started/"
        print_status "Sign in: op signin"
        return 1
    fi

    local agent_toml="${HOME}/.config/1Password/ssh/agent.toml"

    print_header "1Password SSH Agent Configuration"
    print_divider
    echo ""
    echo "Add the following to: ${agent_toml}"
    echo ""
    print_highlight "[[ssh-keys]]"
    print_highlight "item = \"netbird-<project-name>\""
    print_highlight "vault = \"${vault}\""
    echo ""
    print_divider
    print_status "Also ensure these settings are enabled:"
    echo "  1. Open 1Password > Settings > Developer"
    echo "  2. Enable 'Use the SSH agent'"
    echo "  3. Enable 'Integrate with 1Password CLI'"
    echo ""
    print_status "Set your SSH_AUTH_SOCK to use the 1Password agent:"
    print_highlight "  export SSH_AUTH_SOCK=\"$(_1p_agent_sock)\""
    print_divider
}

###############################################################################
# Main
###############################################################################

main() {
    local command=""

    # Parse global options and extract the command
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                return 0
                ;;
            -v|--verbose)
                VERBOSE=1
                set -x
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                echo ""
                usage
                return 1
                ;;
            *)
                command="$1"
                shift
                break
                ;;
        esac
    done

    # If no command provided, show help
    if [[ -z "${command}" ]]; then
        usage
        return 0
    fi

    # Dispatch to the appropriate command handler
    case "${command}" in
        init)
            cmd_init "$@"
            ;;
        connect)
            cmd_connect "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        remove)
            cmd_remove "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        export-config)
            cmd_export_config "$@"
            ;;
        setup-deploy-user)
            cmd_setup_deploy_user "$@"
            ;;
        agent-config)
            cmd_agent_config "$@"
            ;;
        *)
            print_error "Unknown command: ${command}"
            echo ""
            usage
            return 1
            ;;
    esac
}

main "$@"
