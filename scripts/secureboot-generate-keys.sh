#!/usr/bin/env bash
#
# secureboot-generate-keys.sh - Generate custom Secure Boot keys (PK, KEK, db)
#
# Usage: secureboot-generate-keys.sh [--output-dir PATH] [--force]
#
# Exit codes:
#   0 - Success
#   1 - Pre-condition failed
#   2 - Keys already exist
#   3 - Generation failed
#   4 - Permission error
#

set -euo pipefail

# Get script directory for sourcing common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/secureboot-common.sh"

# Default values
OUTPUT_DIR="/var/lib/sbctl"
FORCE=false
START_TIME=$(date +%s)

# T010: Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate custom Secure Boot keys (PK, KEK, db) using sbctl.

OPTIONS:
    --output-dir PATH    Directory to store generated keys (default: /var/lib/sbctl)
    --force              Overwrite existing keys if present
    --help, -h           Show this help message

EXAMPLES:
    # Generate keys in default location
    sudo $(basename "$0")

    # Generate keys in custom location
    sudo $(basename "$0") --output-dir /vms/test-vm/secureboot

    # Force regeneration
    sudo $(basename "$0") --force

EXIT CODES:
    0  - Success
    1  - Pre-condition failed (sbctl not installed, not root, etc.)
    2  - Keys already exist (use --force to overwrite)
    3  - Generation failed
    4  - Permission error

OUTPUT:
    JSON format on success with key file paths and generation time.
    JSON error format on stderr for failures.

For more information, see: specs/004-specify-scripts-bash/quickstart.md
EOF
            exit 0
            ;;
        *)
            error_json $PRECONDITION_FAILED \
                "Unknown option: $1" \
                "{\"arg\": \"$1\"}" \
                "Run with --help for usage information"
            exit $PRECONDITION_FAILED
            ;;
    esac
done

# T011: Pre-condition checks
info_msg "Checking pre-conditions..."

if ! check_root; then
    exit $PRECONDITION_FAILED
fi

if ! check_sbctl; then
    exit $PRECONDITION_FAILED
fi

if ! check_writable_dir "$OUTPUT_DIR"; then
    exit $PRECONDITION_FAILED
fi

# T012: Existing key detection
if [[ -d "$OUTPUT_DIR/keys" ]] && [[ "$FORCE" != true ]]; then
    # Check if any key files exist
    if ls "$OUTPUT_DIR/keys"/*/PK.key "$OUTPUT_DIR/keys"/*/KEK.key "$OUTPUT_DIR/keys"/*/db.key &> /dev/null; then
        existing_keys=$(find "$OUTPUT_DIR/keys" -name "*.key" -type f 2>/dev/null || echo "")
        error_json $ALREADY_EXISTS \
            "Keys already exist at $OUTPUT_DIR/keys/. Use --force to overwrite." \
            "{\"existingKeys\": [$(echo "$existing_keys" | tr '\n' ',' | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g')]}" \
            "Use --force flag to regenerate keys or remove existing keys: rm -rf $OUTPUT_DIR/keys"
        exit $ALREADY_EXISTS
    fi
fi

# T013: sbctl create-keys invocation
info_msg "Generating Secure Boot keys..."

if [[ "$FORCE" == true ]] && [[ -d "$OUTPUT_DIR/keys" ]]; then
    warn_msg "Removing existing keys (--force specified)"
    rm -rf "$OUTPUT_DIR/keys"
    rm -f "$OUTPUT_DIR/GUID"
fi

# Run sbctl create-keys
if ! sbctl create-keys 2>&1; then
    error_json $OPERATION_FAILED \
        "sbctl create-keys command failed" \
        "{\"outputDir\": \"$OUTPUT_DIR\"}" \
        "Check sbctl installation and permissions"
    exit $OPERATION_FAILED
fi

# T014: Post-generation validation
info_msg "Validating generated keys..."

# Check that all expected files were created
expected_files=(
    "$OUTPUT_DIR/keys/PK/PK.key"
    "$OUTPUT_DIR/keys/PK/PK.pem"
    "$OUTPUT_DIR/keys/PK/PK.auth"
    "$OUTPUT_DIR/keys/PK/PK.esl"
    "$OUTPUT_DIR/keys/KEK/KEK.key"
    "$OUTPUT_DIR/keys/KEK/KEK.pem"
    "$OUTPUT_DIR/keys/KEK/KEK.auth"
    "$OUTPUT_DIR/keys/KEK/KEK.esl"
    "$OUTPUT_DIR/keys/db/db.key"
    "$OUTPUT_DIR/keys/db/db.pem"
    "$OUTPUT_DIR/keys/db/db.auth"
    "$OUTPUT_DIR/keys/db/db.esl"
)

missing_files=()
for file in "${expected_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    error_json $VERIFICATION_FAILED \
        "Key generation incomplete - some files missing" \
        "{\"missingFiles\": [$(printf '"%s",' "${missing_files[@]}" | sed 's/,$//')], \"expected\": 12, \"found\": $((12 - ${#missing_files[@]}))}" \
        "Re-run key generation or check sbctl logs"
    exit $VERIFICATION_FAILED
fi

# Check permissions on private keys (should be 600)
permission_errors=()
for key_type in PK KEK db; do
    key_file="$OUTPUT_DIR/keys/$key_type/$key_type.key"
    perms=$(stat -c '%a' "$key_file")
    if [[ "$perms" != "600" ]]; then
        permission_errors+=("{\"file\": \"$key_file\", \"expected\": \"600\", \"actual\": \"$perms\"}")
        # Fix permissions
        chmod 600 "$key_file"
    fi
done

# Check GUID file
if [[ ! -f "$OUTPUT_DIR/GUID" ]]; then
    warn_msg "GUID file not found at $OUTPUT_DIR/GUID"
fi

OWNER_GUID=$(cat "$OUTPUT_DIR/GUID" 2>/dev/null || echo "unknown")

# T017: Performance tracking
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

success_msg "Keys generated successfully in ${DURATION}s"

# T015: JSON success output
success_json "$(cat <<EOF
  "ownerGUID": "$OWNER_GUID",
  "keysGenerated": {
    "PK": {
      "privateKey": "$OUTPUT_DIR/keys/PK/PK.key",
      "publicKey": "$OUTPUT_DIR/keys/PK/PK.pem",
      "authFile": "$OUTPUT_DIR/keys/PK/PK.auth",
      "eslFile": "$OUTPUT_DIR/keys/PK/PK.esl"
    },
    "KEK": {
      "privateKey": "$OUTPUT_DIR/keys/KEK/KEK.key",
      "publicKey": "$OUTPUT_DIR/keys/KEK/KEK.pem",
      "authFile": "$OUTPUT_DIR/keys/KEK/KEK.auth",
      "eslFile": "$OUTPUT_DIR/keys/KEK/KEK.esl"
    },
    "db": {
      "privateKey": "$OUTPUT_DIR/keys/db/db.key",
      "publicKey": "$OUTPUT_DIR/keys/db/db.pem",
      "authFile": "$OUTPUT_DIR/keys/db/db.auth",
      "eslFile": "$OUTPUT_DIR/keys/db/db.esl"
    }
  },
  "durationSeconds": $DURATION
EOF
)"

exit $SUCCESS
