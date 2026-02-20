#!/usr/bin/env bash
# output-helpers.sh - Shared color output functions for all deployment scripts
# Source this file: source "$(dirname "$0")/lib/output-helpers.sh"

# Prevent double-sourcing
[[ -n "${_OUTPUT_HELPERS_LOADED:-}" ]] && return 0
_OUTPUT_HELPERS_LOADED=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

# Prompt helper: read yes/no with default
read_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    while true; do
        if [ "$default" = "y" ]; then
            read -p "$prompt (Y/n): " -r REPLY
        else
            read -p "$prompt (y/N): " -r REPLY
        fi

        # If empty, use default
        if [ -z "$REPLY" ]; then
            [[ "$default" = "y" ]] && return 0 || return 1
        fi

        case $REPLY in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Print a section divider
print_divider() {
    echo -e "${PURPLE}$(printf '=%.0s' {1..60})${NC}"
}

# Command existence check
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

DEPLOYER_REPO="Panoptic-IT-Solutions/netbird-selfhosted-deployer"

# Check for a newer release on GitHub and prompt the user to update
# Usage: check_for_updates <current_version>
check_for_updates() {
    local current_version="${1:?current_version required}"

    # Need curl for the API call
    command_exists curl || return 0

    # Fetch latest release tag (silent fail — never block on network issues)
    local latest_tag
    latest_tag="$(curl -fsSL --connect-timeout 5 --max-time 10 \
        "https://api.github.com/repos/${DEPLOYER_REPO}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"//; s/".*//')" || true

    # Fallback to tags API if no releases exist
    if [[ -z "${latest_tag}" ]]; then
        latest_tag="$(curl -fsSL --connect-timeout 5 --max-time 10 \
            "https://api.github.com/repos/${DEPLOYER_REPO}/tags" 2>/dev/null \
            | grep '"name"' | head -1 | sed 's/.*"name":[[:space:]]*"//; s/".*//')" || true
    fi

    local latest_version="${latest_tag#v}"

    # If we couldn't determine the latest version, skip silently
    [[ -z "${latest_version}" ]] && return 0

    # Already up to date
    [[ "${current_version}" == "${latest_version}" ]] && return 0

    # Compare with sort -V (version sort)
    local newest
    newest="$(printf '%s\n%s\n' "${current_version}" "${latest_version}" | sort -V | tail -1)"

    if [[ "${newest}" != "${current_version}" ]]; then
        print_warning "A newer version is available: v${latest_version} (current: v${current_version})"
        print_status "Update: curl -fsSL https://raw.githubusercontent.com/${DEPLOYER_REPO}/main/install.sh | bash"
        echo ""
        if ! read_yes_no "Continue with current version?" "y"; then
            print_status "Exiting. Run the update command above to upgrade."
            exit 0
        fi
        echo ""
    fi

    return 0
}
