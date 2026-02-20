#!/usr/bin/env bash
# install-deps.sh - Automatic dependency installation library for Netbird deployment scripts
# Source this file from deploy scripts: source "${LIB_DIR}/install-deps.sh"

# Prevent double-sourcing
[[ -n "${_INSTALL_DEPS_LOADED:-}" ]] && return 0
_INSTALL_DEPS_LOADED=1

# Resolve library directory and source output helpers
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/output-helpers.sh"

###############################################################################
# OS Detection
###############################################################################

_detect_os() {
    local kernel
    kernel="$(uname -s)"

    if [[ "$kernel" == "Darwin" ]]; then
        echo "macos"
        return 0
    fi

    if [[ "$kernel" == "Linux" ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            echo "ubuntu"
        elif command -v dnf >/dev/null 2>&1; then
            echo "centos"
        elif command -v yum >/dev/null 2>&1; then
            echo "centos"
        else
            echo "linux"
        fi
        return 0
    fi

    echo "linux"
    return 0
}

###############################################################################
# Dependency Checking
###############################################################################

# check_dependency(name) - returns 0 if installed, 1 if not
check_dependency() {
    local name="$1"

    case "$name" in
        "docker compose")
            docker compose version >/dev/null 2>&1
            return $?
            ;;
        *)
            command -v "$name" >/dev/null 2>&1
            return $?
            ;;
    esac
}

###############################################################################
# macOS: Homebrew
###############################################################################

_ensure_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi

    print_status "Homebrew is not installed. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Source Homebrew shellenv for Apple Silicon and Intel Macs
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if ! command -v brew >/dev/null 2>&1; then
        print_error "Homebrew installation failed."
        return 1
    fi

    print_success "Homebrew installed successfully."
    return 0
}

###############################################################################
# Linux: hcloud binary from GitHub Releases
###############################################################################

_install_hcloud_linux() {
    print_status "Installing hcloud CLI from GitHub releases..."

    local latest_version
    latest_version="$(curl -fsSL https://api.github.com/repos/hetznercloud/cli/releases/latest | jq -r '.tag_name' 2>/dev/null)"

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch latest hcloud version from GitHub API."
        print_error "Ensure jq and curl are available, and you have internet access."
        return 1
    fi

    # Strip leading 'v' for download URL
    local version_number="${latest_version#v}"
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm" ;;
    esac

    local download_url="https://github.com/hetznercloud/cli/releases/download/${latest_version}/hcloud-linux-${arch}.tar.gz"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    print_status "Downloading hcloud ${latest_version} for linux/${arch}..."
    if ! curl -fsSL "$download_url" -o "${tmp_dir}/hcloud.tar.gz"; then
        print_error "Failed to download hcloud binary."
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf "${tmp_dir}/hcloud.tar.gz" -C "$tmp_dir"

    if [[ -f "${tmp_dir}/hcloud" ]]; then
        sudo mv "${tmp_dir}/hcloud" /usr/local/bin/hcloud
        sudo chmod +x /usr/local/bin/hcloud
    else
        print_error "hcloud binary not found in archive."
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    if command -v hcloud >/dev/null 2>&1; then
        print_success "hcloud $(hcloud version 2>/dev/null || echo "${latest_version}") installed successfully."
        return 0
    else
        print_error "hcloud installation failed."
        return 1
    fi
}

###############################################################################
# Linux: 1Password CLI
###############################################################################

_install_op_linux() {
    print_status "Installing 1Password CLI..."

    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm" ;;
    esac

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local download_url="https://cache.agilebits.com/dist/1P/op2/pkg/v2.30.0/op_linux_${arch}_v2.30.0.zip"

    print_status "Downloading 1Password CLI for linux/${arch}..."
    if ! curl -fsSL "$download_url" -o "${tmp_dir}/op.zip"; then
        print_error "Failed to download 1Password CLI."
        rm -rf "$tmp_dir"
        return 1
    fi

    if command -v unzip >/dev/null 2>&1; then
        unzip -o "${tmp_dir}/op.zip" -d "$tmp_dir" >/dev/null 2>&1
    else
        print_error "unzip is required to install 1Password CLI. Install it first."
        rm -rf "$tmp_dir"
        return 1
    fi

    if [[ -f "${tmp_dir}/op" ]]; then
        sudo mv "${tmp_dir}/op" /usr/local/bin/op
        sudo chmod +x /usr/local/bin/op
    else
        print_error "op binary not found in archive."
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    if command -v op >/dev/null 2>&1; then
        print_success "1Password CLI installed successfully."
        return 0
    else
        print_error "1Password CLI installation failed."
        return 1
    fi
}

###############################################################################
# Single dependency installer
###############################################################################

_install_dependency() {
    local name="$1"
    local os="$2"

    print_status "Installing ${name}..."

    case "$name" in
        brew)
            _ensure_homebrew
            return $?
            ;;
        hcloud)
            if [[ "$os" == "macos" ]]; then
                _ensure_homebrew || return 1
                brew install hcloud
            else
                _install_hcloud_linux
            fi
            ;;
        az)
            if [[ "$os" == "macos" ]]; then
                _ensure_homebrew || return 1
                brew install azure-cli
            elif [[ "$os" == "ubuntu" ]]; then
                curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
            else
                print_error "Azure CLI auto-install is only supported on macOS and Debian/Ubuntu."
                print_error "Visit https://learn.microsoft.com/en-us/cli/azure/install-azure-cli for other platforms."
                return 1
            fi
            ;;
        op)
            if [[ "$os" == "macos" ]]; then
                _ensure_homebrew || return 1
                brew install 1password-cli
            else
                _install_op_linux
            fi
            ;;
        jq)
            if [[ "$os" == "macos" ]]; then
                _ensure_homebrew || return 1
                brew install jq
            elif [[ "$os" == "ubuntu" ]]; then
                sudo apt-get update -qq && sudo apt-get install -y jq
            elif [[ "$os" == "centos" ]]; then
                sudo yum install -y jq
            else
                print_error "Cannot auto-install jq on this platform."
                return 1
            fi
            ;;
        dig)
            if [[ "$os" == "macos" ]]; then
                _ensure_homebrew || return 1
                brew install bind
            elif [[ "$os" == "ubuntu" ]]; then
                sudo apt-get update -qq && sudo apt-get install -y dnsutils
            elif [[ "$os" == "centos" ]]; then
                sudo yum install -y bind-utils
            else
                print_error "Cannot auto-install dig on this platform."
                return 1
            fi
            ;;
        docker)
            if [[ "$os" == "macos" ]]; then
                print_warning "Docker Desktop must be installed manually on macOS."
                print_status "Download from: https://www.docker.com/products/docker-desktop/"
                print_status "After installing Docker Desktop, restart your terminal and re-run this script."
                return 1
            elif [[ "$os" == "ubuntu" ]]; then
                sudo apt-get update -qq && sudo apt-get install -y docker.io
                sudo systemctl enable --now docker 2>/dev/null || true
            elif [[ "$os" == "centos" ]]; then
                sudo yum install -y docker
                sudo systemctl enable --now docker 2>/dev/null || true
            else
                print_error "Cannot auto-install Docker on this platform."
                return 1
            fi
            ;;
        "docker compose")
            if [[ "$os" == "macos" ]]; then
                print_warning "Docker Compose is included with Docker Desktop on macOS."
                print_status "Install Docker Desktop first: https://www.docker.com/products/docker-desktop/"
                return 1
            elif [[ "$os" == "ubuntu" ]]; then
                sudo apt-get update -qq && sudo apt-get install -y docker-compose-plugin
            elif [[ "$os" == "centos" ]]; then
                sudo yum install -y docker-compose-plugin
            else
                print_error "Cannot auto-install Docker Compose on this platform."
                return 1
            fi
            ;;
        ssh-keygen)
            if [[ "$os" == "macos" ]]; then
                print_warning "ssh-keygen should be pre-installed on macOS."
                print_status "If missing, reinstall macOS Command Line Tools: xcode-select --install"
                return 1
            elif [[ "$os" == "ubuntu" ]]; then
                sudo apt-get update -qq && sudo apt-get install -y openssh-client
            elif [[ "$os" == "centos" ]]; then
                sudo yum install -y openssh-clients
            else
                print_error "Cannot auto-install ssh-keygen on this platform."
                return 1
            fi
            ;;
        *)
            print_error "Unknown dependency: ${name}"
            return 1
            ;;
    esac

    # Verify installation succeeded
    if check_dependency "$name"; then
        print_success "${name} installed successfully."
        return 0
    else
        print_error "${name} installation could not be verified."
        return 1
    fi
}

###############################################################################
# Manual install instructions (printed when user declines auto-install)
###############################################################################

_print_manual_instructions() {
    local name="$1"
    local os="$2"

    case "$name" in
        brew)
            echo "  brew:           /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            ;;
        hcloud)
            if [[ "$os" == "macos" ]]; then
                echo "  hcloud:         brew install hcloud"
            else
                echo "  hcloud:         Download from https://github.com/hetznercloud/cli/releases"
            fi
            ;;
        az)
            if [[ "$os" == "macos" ]]; then
                echo "  az (Azure CLI): brew install azure-cli"
            else
                echo "  az (Azure CLI): https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
            fi
            ;;
        op)
            if [[ "$os" == "macos" ]]; then
                echo "  op (1Password):  brew install 1password-cli"
            else
                echo "  op (1Password):  https://1password.com/downloads/command-line"
            fi
            ;;
        jq)
            if [[ "$os" == "macos" ]]; then
                echo "  jq:             brew install jq"
            else
                echo "  jq:             apt-get install -y jq  /  yum install -y jq"
            fi
            ;;
        dig)
            if [[ "$os" == "macos" ]]; then
                echo "  dig:            brew install bind"
            else
                echo "  dig:            apt-get install -y dnsutils"
            fi
            ;;
        docker)
            if [[ "$os" == "macos" ]]; then
                echo "  docker:         https://www.docker.com/products/docker-desktop/"
            else
                echo "  docker:         apt-get install -y docker.io"
            fi
            ;;
        "docker compose")
            if [[ "$os" == "macos" ]]; then
                echo "  docker compose: Included with Docker Desktop"
            else
                echo "  docker compose: apt-get install -y docker-compose-plugin"
            fi
            ;;
        ssh-keygen)
            if [[ "$os" == "macos" ]]; then
                echo "  ssh-keygen:     xcode-select --install"
            else
                echo "  ssh-keygen:     apt-get install -y openssh-client"
            fi
            ;;
    esac
}

###############################################################################
# Dependency description for display
###############################################################################

_dep_description() {
    local name="$1"
    case "$name" in
        brew)             echo "Homebrew package manager (macOS)" ;;
        hcloud)           echo "Hetzner Cloud CLI" ;;
        az)               echo "Azure CLI" ;;
        op)               echo "1Password CLI" ;;
        jq)               echo "JSON processor" ;;
        dig)              echo "DNS lookup utility" ;;
        docker)           echo "Container runtime" ;;
        "docker compose") echo "Docker Compose plugin" ;;
        ssh-keygen)       echo "SSH key generation tool" ;;
        *)                echo "$name" ;;
    esac
}

###############################################################################
# Ensure 1Password CLI is signed in
###############################################################################

_ensure_op_signin() {
    # Skip if op is not installed
    command -v op >/dev/null 2>&1 || return 0

    # Already signed in?
    if op whoami >/dev/null 2>&1; then
        print_success "1Password CLI is signed in."
        return 0
    fi

    print_warning "1Password CLI is installed but not signed in."
    print_status "SSH keys will be stored in 1Password for secure sharing with colleagues."
    echo ""

    # Disable set -e for this section since op commands return non-zero when not signed in
    set +e

    local max_attempts=3
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))
        print_status "Signing in to 1Password (attempt ${attempt}/${max_attempts})..."
        print_status "A 1Password prompt should appear — authenticate to continue."
        echo ""

        # Run op signin directly so the user can interact with it
        op signin

        # Check if sign-in succeeded
        if op whoami >/dev/null 2>&1; then
            print_success "1Password CLI signed in successfully."
            # Reset SSH backend cache so it picks up 1Password mode
            SSH_BACKEND=""
            set -e
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            print_warning "Sign-in failed. Please try again."
            echo ""
        fi
    done

    set -e
    print_error "Failed to sign in to 1Password CLI after ${max_attempts} attempts."
    print_error "Please sign in manually with 'eval \$(op signin)' and re-run the script."
    return 1
}

###############################################################################
# Main: preflight_check_and_install
#   $1 = context: "full" (default) or "server-only" (skip docker/compose)
###############################################################################

preflight_check_and_install() {
    local context="${1:-full}"
    local os
    os="$(_detect_os)"

    print_header "Checking dependencies..."
    print_status "Detected OS: ${os}"
    echo ""

    # Build the list of dependencies to check based on context
    local -a all_deps=()
    local -A dep_category=()

    # On macOS, Homebrew is a prerequisite for everything else
    if [[ "$os" == "macos" ]]; then
        all_deps+=("brew")
        dep_category["brew"]="required"
    fi

    all_deps+=("hcloud")
    dep_category["hcloud"]="required"

    all_deps+=("az")
    dep_category["az"]="recommended"

    all_deps+=("op")
    dep_category["op"]="recommended"

    all_deps+=("jq")
    dep_category["jq"]="required"

    all_deps+=("dig")
    dep_category["dig"]="recommended"

    if [[ "$context" == "full" ]]; then
        all_deps+=("docker")
        dep_category["docker"]="required"

        all_deps+=("docker compose")
        dep_category["docker compose"]="required"
    fi

    all_deps+=("ssh-keygen")
    dep_category["ssh-keygen"]="required"

    # Check each dependency
    local -a missing_required=()
    local -a missing_recommended=()
    local -a found_deps=()
    local has_missing=false

    for dep in "${all_deps[@]}"; do
        if check_dependency "$dep"; then
            found_deps+=("$dep")
        else
            has_missing=true
            if [[ "${dep_category[$dep]}" == "required" ]]; then
                missing_required+=("$dep")
            else
                missing_recommended+=("$dep")
            fi
        fi
    done

    # Print status of all dependencies
    for dep in "${all_deps[@]}"; do
        local category="${dep_category[$dep]}"
        if check_dependency "$dep"; then
            echo -e "  ${GREEN}[OK]${NC}       ${dep}  $(printf '%-25s' "$(_dep_description "$dep")")  (${category})"
        else
            if [[ "$category" == "required" ]]; then
                echo -e "  ${RED}[MISSING]${NC}  ${dep}  $(printf '%-25s' "$(_dep_description "$dep")")  (${category})"
            else
                echo -e "  ${YELLOW}[MISSING]${NC}  ${dep}  $(printf '%-25s' "$(_dep_description "$dep")")  (${category})"
            fi
        fi
    done
    echo ""

    # If nothing is missing, we are done
    if [[ "$has_missing" == false ]]; then
        print_success "All dependencies are installed."

        # Ensure 1Password CLI is signed in
        _ensure_op_signin || return 1

        return 0
    fi

    # Summarize what is missing
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_required[*]}"
    fi
    if [[ ${#missing_recommended[@]} -gt 0 ]]; then
        print_warning "Missing recommended dependencies: ${missing_recommended[*]}"
    fi
    echo ""

    # Prompt user
    local all_missing=("${missing_required[@]}" "${missing_recommended[@]}")

    if read_yes_no "Install all missing dependencies now?" "y"; then
        # On macOS ensure Homebrew is available before installing anything else
        if [[ "$os" == "macos" ]]; then
            _ensure_homebrew || {
                print_error "Cannot proceed without Homebrew on macOS."
                return 1
            }
        fi

        local install_failures=()
        for dep in "${all_missing[@]}"; do
            # Skip brew - already handled above
            [[ "$dep" == "brew" ]] && continue

            if ! _install_dependency "$dep" "$os"; then
                install_failures+=("$dep")
            fi
            echo ""
        done

        # Report results
        if [[ ${#install_failures[@]} -gt 0 ]]; then
            print_warning "Some dependencies could not be installed automatically: ${install_failures[*]}"
            print_status "Manual installation instructions:"
            for dep in "${install_failures[@]}"; do
                _print_manual_instructions "$dep" "$os"
            done
            echo ""

            # Check if any failures were required
            local has_required_failure=false
            for dep in "${install_failures[@]}"; do
                if [[ "${dep_category[$dep]}" == "required" ]]; then
                    has_required_failure=true
                    break
                fi
            done

            if [[ "$has_required_failure" == true ]]; then
                print_error "Required dependencies are still missing. Cannot continue."
                return 1
            else
                print_warning "Only recommended dependencies are missing. Continuing with reduced functionality."
                return 0
            fi
        fi

        print_success "All dependencies installed successfully."

        # Ensure 1Password CLI is signed in
        _ensure_op_signin || return 1

        return 0
    else
        # User declined auto-install
        if [[ ${#missing_required[@]} -gt 0 ]]; then
            print_error "Required dependencies must be installed before continuing."
            print_status "Install them manually:"
            echo ""
            for dep in "${missing_required[@]}"; do
                _print_manual_instructions "$dep" "$os"
            done
            echo ""
            return 1
        fi

        if [[ ${#missing_recommended[@]} -gt 0 ]]; then
            print_warning "Continuing without recommended dependencies: ${missing_recommended[*]}"
            print_status "You can install them later:"
            echo ""
            for dep in "${missing_recommended[@]}"; do
                _print_manual_instructions "$dep" "$os"
            done
            echo ""
            return 0
        fi
    fi

    return 0
}
