#!/usr/bin/env bash
# TPM Enrollment Status Check and Warning Banner
# Called by environment.interactiveShellInit on interactive shell login.
#
# This script only checks the marker file — the actual LUKS header inspection
# runs as root via the keystone-tpm-check systemd oneshot service at boot.
# This avoids the permission issue where regular users cannot read block devices,
# which caused cryptsetup luksDump to fail silently and show the banner even
# when TPM was fully enrolled.

set -euo pipefail

# Marker file maintained by systemd service (runs as root at boot)
MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"

if [[ -f "$MARKER_FILE" ]]; then
  exit 0
fi

# TPM not enrolled — display warning banner
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
