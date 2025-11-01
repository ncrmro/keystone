#!/usr/bin/env bash
#
# Common functions and constants for Secure Boot scripts
# Source this file in other secureboot-*.sh scripts
#

# Exit codes (T008)
readonly SUCCESS=0
readonly PRECONDITION_FAILED=1
readonly ALREADY_EXISTS=2
readonly OPERATION_FAILED=3
readonly VERIFICATION_FAILED=4
readonly EXPECTED_MISMATCH=10

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# T006: Error handling helper functions for JSON error output
error_json() {
    local code=$1
    local message=$2
    local context=${3:-"{}"}
    local suggestion=${4:-""}

    cat >&2 <<EOF
{
  "status": "error",
  "code": $code,
  "message": "$message",
  "context": $context,
  "suggestion": "$suggestion"
}
EOF
}

# Success JSON output helper
success_json() {
    local data=${1:-"{}"}
    cat <<EOF
{
  "status": "success",
  $data
}
EOF
}

# Print error message to stderr
error_msg() {
    echo -e "${RED}Error: $*${NC}" >&2
}

# Print success message
success_msg() {
    echo -e "${GREEN}✓ $*${NC}"
}

# Print info message
info_msg() {
    echo -e "${BLUE}ℹ $*${NC}"
}

# Print warning message
warn_msg() {
    echo -e "${YELLOW}⚠ $*${NC}"
}

# T007: Pre-condition check functions

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_json $PRECONDITION_FAILED \
            "This script must be run as root" \
            "{\"currentUser\": \"$(whoami)\", \"uid\": $EUID}" \
            "Run with sudo or as root user"
        return 1
    fi
    return 0
}

# Check if sbctl is available
check_sbctl() {
    if ! command -v sbctl &> /dev/null; then
        error_json $PRECONDITION_FAILED \
            "sbctl command not found" \
            "{\"path\": \"$PATH\"}" \
            "Install sbctl: nix-shell -p sbctl"
        return 1
    fi
    return 0
}

# Check if bootctl is available
check_bootctl() {
    if ! command -v bootctl &> /dev/null; then
        error_json $PRECONDITION_FAILED \
            "bootctl command not found" \
            "{\"path\": \"$PATH\"}" \
            "bootctl is part of systemd-boot, ensure systemd is installed"
        return 1
    fi
    return 0
}

# Check if EFI variables are mounted
check_efivars() {
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        error_json $PRECONDITION_FAILED \
            "EFI variables directory not found - not a UEFI system or efivars not mounted" \
            "{\"expectedPath\": \"/sys/firmware/efi/efivars\"}" \
            "Ensure system is booted in UEFI mode and efivars filesystem is mounted"
        return 1
    fi

    # Check if efivars is writable
    if [[ ! -w /sys/firmware/efi/efivars ]]; then
        error_json $PRECONDITION_FAILED \
            "EFI variables directory is not writable" \
            "{\"path\": \"/sys/firmware/efi/efivars\"}" \
            "Mount efivars with write access or run as root"
        return 1
    fi

    return 0
}

# Check if directory is writable
check_writable_dir() {
    local dir=$1
    local parent_dir=$(dirname "$dir")

    if [[ ! -d "$parent_dir" ]]; then
        error_json $PRECONDITION_FAILED \
            "Parent directory does not exist: $parent_dir" \
            "{\"directory\": \"$parent_dir\"}" \
            "Create parent directory: mkdir -p $parent_dir"
        return 1
    fi

    if [[ ! -w "$parent_dir" ]]; then
        error_json $PRECONDITION_FAILED \
            "Parent directory is not writable: $parent_dir" \
            "{\"directory\": \"$parent_dir\", \"permissions\": \"$(stat -c '%a' "$parent_dir")\"}" \
            "Ensure directory has write permissions"
        return 1
    fi

    return 0
}

# Get Setup Mode status (0 = User Mode, 1 = Setup Mode)
get_setup_mode() {
    local setupmode_file="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    if [[ ! -f "$setupmode_file" ]]; then
        echo "unknown"
        return 1
    fi

    # Read the last byte of the file (the actual value)
    local value=$(od --address-radix=n --format=u1 "$setupmode_file" | awk '{print $NF}')
    echo "$value"
    return 0
}

# Get Secure Boot status (0 = Disabled, 1 = Enabled)
get_secureboot_status() {
    local secureboot_file="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    if [[ ! -f "$secureboot_file" ]]; then
        echo "unknown"
        return 1
    fi

    # Read the last byte of the file (the actual value)
    local value=$(od --address-radix=n --format=u1 "$secureboot_file" | awk '{print $NF}')
    echo "$value"
    return 0
}

# vim: set ft=bash:
