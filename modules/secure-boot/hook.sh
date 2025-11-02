#!/usr/bin/env bash
# Secure Boot Hook Script for Disko
# Generates and enrolls Secure Boot keys during nixos-anywhere deployment

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration passed from Nix module
PKI_BUNDLE="${PKI_BUNDLE:-/var/lib/sbctl}"
INCLUDE_MS="${INCLUDE_MS:-false}"
AUTO_ENROLL="${AUTO_ENROLL:-true}"

# Target filesystem root (set by disko)
TARGET_ROOT="${TARGET_ROOT:-/mnt}"

# Key generation function
generate_keys() {
    log_info "Generating Secure Boot keys..."

    local target_pki="$TARGET_ROOT$PKI_BUNDLE"

    # Check if keys already exist
    if [ -d "$target_pki/keys" ]; then
        log_warn "Keys already exist at $target_pki/keys"
        return 0
    fi

    # Create PKI directory structure
    log_info "Creating PKI directory at $target_pki"
    mkdir -p "$target_pki"

    # Generate keys using sbctl
    log_info "Running sbctl to generate keys..."
    if ! sbctl create-keys --export "$target_pki"; then
        log_error "Failed to generate keys with sbctl"
        return 1
    fi

    # Verify key generation
    local required_keys=("PK/PK.key" "PK/PK.crt" "KEK/KEK.key" "KEK/KEK.crt" "db/db.key" "db/db.crt")
    for key_file in "${required_keys[@]}"; do
        if [ ! -f "$target_pki/keys/$key_file" ]; then
            log_error "Missing required key file: $key_file"
            return 1
        fi
    done

    log_info "Successfully generated Secure Boot keys"
    return 0
}

# Setup Mode detection
check_setup_mode() {
    log_info "Checking UEFI Setup Mode status..."

    # Check if EFI variables are available
    if [ ! -d "/sys/firmware/efi/efivars" ]; then
        log_error "EFI variables not accessible - system may not be UEFI"
        return 2
    fi

    # Read SetupMode variable
    local setup_mode_var="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    if [ ! -f "$setup_mode_var" ]; then
        log_warn "SetupMode variable not found"
        return 1
    fi

    # Extract the value (last byte of the variable)
    local setup_mode_value
    setup_mode_value=$(od --address-radix=n --format=u1 "$setup_mode_var" 2>/dev/null | awk '{print $NF}')

    if [ "$setup_mode_value" = "1" ]; then
        log_info "System is in Setup Mode (ready for key enrollment)"
        return 0
    elif [ "$setup_mode_value" = "0" ]; then
        log_warn "System is in User Mode (keys already enrolled)"
        return 1
    else
        log_warn "Unknown SetupMode value: $setup_mode_value"
        return 1
    fi
}

# Key enrollment function (implemented in T012)
enroll_keys() {
    log_info "Enrolling keys in UEFI firmware..."
    # Implementation in T012
}

# Error handler
handle_error() {
    local error_code=$1
    local error_msg=$2
    log_error "$error_msg (code: $error_code)"

    # Clean up partial state if needed
    if [ -d "$TARGET_ROOT$PKI_BUNDLE" ] && [ ! -f "$TARGET_ROOT$PKI_BUNDLE/keys/db/db.crt" ]; then
        log_warn "Cleaning up incomplete PKI directory"
        rm -rf "$TARGET_ROOT$PKI_BUNDLE"
    fi

    exit "$error_code"
}

# Main execution
main() {
    log_info "Starting Secure Boot key provisioning"

    # Check if we're in the right environment
    if [ ! -d "$TARGET_ROOT" ]; then
        handle_error 1 "Target root $TARGET_ROOT does not exist"
    fi

    # Check if sbctl is available
    if ! command -v sbctl >/dev/null 2>&1; then
        handle_error 2 "sbctl command not found - ensure it's in the installer environment"
    fi

    # Check Setup Mode status
    if ! check_setup_mode; then
        local setup_mode_status=$?
        if [ "$setup_mode_status" -eq 2 ]; then
            handle_error 3 "EFI system not detected - Secure Boot requires UEFI"
        elif [ "$setup_mode_status" -eq 1 ] && [ "$AUTO_ENROLL" = "true" ]; then
            log_warn "System not in Setup Mode - skipping automatic enrollment"
            log_info "Keys can be enrolled manually later if needed"
        fi
    fi

    # Generate keys
    if ! generate_keys; then
        handle_error 4 "Key generation failed"
    fi

    # Success message (enrollment will be implemented in US2)
    log_info "Secure Boot key generation completed successfully"
    log_info "Keys stored at: $TARGET_ROOT$PKI_BUNDLE"
}

# Execute main function
main "$@"