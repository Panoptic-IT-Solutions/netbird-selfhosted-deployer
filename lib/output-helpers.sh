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
