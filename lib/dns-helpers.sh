#!/usr/bin/env bash
# dns-helpers.sh - DNS verification and resolution helpers
# Provides functions to verify DNS records point to the expected IP and
# optionally wait for propagation before proceeding with deployment.

# Source guard - prevent double-sourcing
[[ -n "${_DNS_HELPERS_LOADED:-}" ]] && return 0; _DNS_HELPERS_LOADED=1

# Source shared output helpers
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/output-helpers.sh"

# ---------------------------------------------------------------------------
# dns_check_resolution - Resolve a domain to its IP address
#
# Tries dig, then host, then nslookup (in order of preference).
#
# Arguments:
#   $1 - domain: The domain name to resolve
#
# Outputs: The resolved IP address, or empty string if unresolved.
# Returns 0 always (caller checks output).
# ---------------------------------------------------------------------------
dns_check_resolution() {
    local domain="$1"
    local resolved_ip=""

    if [[ -z "$domain" ]]; then
        return 0
    fi

    # Try dig first (most reliable, uses Google DNS)
    if command_exists dig; then
        resolved_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
        if [[ -n "$resolved_ip" ]]; then
            echo "$resolved_ip"
            return 0
        fi
    fi

    # Fall back to host command
    if command_exists host; then
        resolved_ip=$(host "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        if [[ -n "$resolved_ip" ]]; then
            echo "$resolved_ip"
            return 0
        fi
    fi

    # Last resort: nslookup
    if command_exists nslookup; then
        resolved_ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
        if [[ -n "$resolved_ip" ]]; then
            echo "$resolved_ip"
            return 0
        fi
    fi

    # Could not resolve
    echo ""
    return 0
}

# ---------------------------------------------------------------------------
# dns_verify_or_wait - Verify DNS resolution and optionally wait for propagation
#
# Arguments:
#   $1 - domain:          The domain to verify
#   $2 - expected_ip:     The IP address the domain should resolve to
#   $3 - timeout_minutes: (optional) Max minutes to wait, default 10
#   $4 - skip_flag:       (optional) If "true", skip DNS verification entirely
#
# Returns 0 if DNS matches or skip_flag is set, 1 on timeout or user abort.
# ---------------------------------------------------------------------------
dns_verify_or_wait() {
    local domain="$1"
    local expected_ip="$2"
    local timeout_minutes="${3:-10}"
    local skip_flag="${4:-false}"

    if [[ -z "$domain" || -z "$expected_ip" ]]; then
        print_error "Usage: dns_verify_or_wait <domain> <expected_ip> [timeout_minutes] [skip_flag]"
        return 1
    fi

    # Allow skipping DNS verification entirely
    if [[ "$skip_flag" == "true" ]]; then
        print_status "Skipping DNS check for $domain (skip flag set)"
        return 0
    fi

    # Ensure we have at least one DNS resolution tool
    if ! command_exists dig && ! command_exists host && ! command_exists nslookup; then
        print_warning "No DNS resolution tool found (dig, host, or nslookup). Skipping DNS check."
        return 0
    fi

    print_status "Checking DNS for $domain -> $expected_ip ..."

    local resolved_ip
    resolved_ip=$(dns_check_resolution "$domain")

    # Case 1: Resolves to the expected IP
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        print_success "DNS verified: $domain -> $expected_ip"
        return 0
    fi

    # Case 2: Resolves to a different IP
    if [[ -n "$resolved_ip" ]]; then
        print_warning "DNS mismatch for $domain:"
        print_warning "  Current:  $resolved_ip"
        print_warning "  Expected: $expected_ip"
        echo ""

        if read_yes_no "Continue anyway?" "n"; then
            print_warning "Proceeding despite DNS mismatch"
            return 0
        else
            print_error "Aborting due to DNS mismatch"
            return 1
        fi
    fi

    # Case 3: Domain does not resolve at all
    print_warning "Domain $domain does not resolve to any IP address."
    echo ""
    print_header "Please configure DNS for your domain:"
    echo ""
    print_highlight "  Type:  A"
    print_highlight "  Name:  $domain"
    print_highlight "  Value: $expected_ip"
    print_highlight "  TTL:   300"
    echo ""

    if ! read_yes_no "Wait for DNS propagation?" "y"; then
        print_warning "Skipping DNS wait. Domain may not be reachable."
        return 1
    fi

    # Poll for DNS propagation
    local timeout_seconds=$((timeout_minutes * 60))
    local elapsed=0
    local interval=30

    print_status "Waiting up to ${timeout_minutes} minutes for DNS propagation..."

    while [[ $elapsed -lt $timeout_seconds ]]; do
        resolved_ip=$(dns_check_resolution "$domain")

        if [[ "$resolved_ip" == "$expected_ip" ]]; then
            echo ""
            print_success "DNS propagated: $domain -> $expected_ip (took $((elapsed / 60))m $((elapsed % 60))s)"
            return 0
        fi

        local remaining=$(( (timeout_seconds - elapsed) / 60 ))
        printf "\r  Checking... %dm remaining " "$remaining"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo ""
    print_error "DNS propagation timed out after ${timeout_minutes} minutes"
    print_warning "Domain $domain still does not resolve to $expected_ip"
    print_status "You can continue and retry DNS verification later."
    return 1
}
