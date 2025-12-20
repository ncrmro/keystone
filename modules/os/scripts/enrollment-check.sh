#!/usr/bin/env bash
# TPM Enrollment Status Check and Warning Banner
# Called by environment.interactiveShellInit on interactive shell login
# NixOS ensures this only runs for interactive shells - no PS1 check needed

set -euo pipefail

# State marker file location
MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"

# Credstore device (will be substituted by NixOS module)
CREDSTORE_DEVICE="@credstoreDevice@"

# T012: Check if marker file exists
if [[ -f "$MARKER_FILE" ]]; then
  # Marker exists - validate it against actual LUKS header
  # T013: Check LUKS header for systemd-tpm2 token
  if @cryptsetup@ luksDump "$CREDSTORE_DEVICE" 2>/dev/null | grep -q "systemd-tpm2"; then
    # TPM enrolled and marker valid - suppress banner
    exit 0
  else
    # T014: Marker invalid (TPM removed manually) - delete marker and show banner
    rm -f "$MARKER_FILE"
  fi
fi

# T014: Self-healing - check if TPM is actually enrolled but marker missing
if @cryptsetup@ luksDump "$CREDSTORE_DEVICE" 2>/dev/null | grep -q "systemd-tpm2"; then
  # TPM is enrolled but marker wasn't created - create it now (self-healing)
  mkdir -p "$(dirname "$MARKER_FILE")"
  cat > "$MARKER_FILE" <<EOF
TPM enrollment detected: $(date -Iseconds)
Method: auto-detected
Note: Marker file was missing but TPM keyslot found in LUKS header
EOF
  exit 0
fi

# T015: TPM not enrolled - display warning banner
cat <<'EOF'

+--------------------------------------------------------------------------+
| [!] WARNING: TPM ENROLLMENT NOT CONFIGURED                              |
+--------------------------------------------------------------------------+
|                                                                          |
| Your system is using the default LUKS password "keystone" which is      |
| publicly known and provides NO security.                                |
|                                                                          |
| To secure your encrypted disk, you MUST complete TPM enrollment:        |
|                                                                          |
|   Option 1: Generate recovery key (recommended)                         |
|      $ sudo keystone-enroll-recovery                                    |
|                                                                          |
|   Option 2: Set custom password                                         |
|      $ sudo keystone-enroll-password                                    |
|                                                                          |
| After enrollment:                                                        |
|   * Default "keystone" password will be removed                         |
|   * Disk will unlock automatically via TPM on boot                      |
|   * Recovery credential available if TPM fails                          |
|                                                                          |
| Documentation: /usr/share/doc/keystone/tpm-enrollment.md                |
|                                                                          |
+--------------------------------------------------------------------------+

EOF
