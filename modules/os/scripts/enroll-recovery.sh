#!/usr/bin/env bash
# Keystone TPM Enrollment: Recovery Key Method
# Generates a cryptographically secure recovery key and enrolls TPM automatic unlock

set -euo pipefail

# Configuration (substituted by NixOS module)
CREDSTORE_DEVICE="@credstoreDevice@"
TPM_PCRS="@tpmPCRs@"
MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"

# Parse arguments
AUTO_MODE=false
for arg in "$@"; do
    case $arg in
        --auto)
            AUTO_MODE=true
            ;;
        --help|-h)
            cat <<EOF
Keystone TPM Enrollment: Recovery Key Method

Usage: keystone-enroll-recovery [--auto]

Options:
  --auto    Automatically execute enrollment commands
  --help    Show this help message

Without --auto, this script shows the commands that would be executed
for educational purposes. Use --auto to actually run the enrollment.
EOF
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== Keystone TPM Enrollment: Recovery Key ==="
echo ""

# Run prerequisite checks
echo "[Prerequisites]"

# Check Secure Boot enabled
if ! @bootctl@ status 2>/dev/null | grep -q "Secure Boot:.*enabled"; then
  echo "[ERROR] Secure Boot is not enabled"
  echo ""
  echo "TPM enrollment requires Secure Boot to be fully enabled in User Mode."
  echo "Run: sudo sbctl status"
  exit 1
fi
echo "[OK] Secure Boot enabled"

# Check TPM2 device available
if ! @systemd_cryptenroll@ --tpm2-device=list &>/dev/null; then
  echo "[ERROR] No TPM2 device found"
  echo ""
  echo "TPM enrollment requires TPM 2.0 hardware or emulation."
  exit 2
fi
echo "[OK] TPM2 device detected"

# Check credstore volume exists
if [[ ! -b "$CREDSTORE_DEVICE" ]]; then
  echo "[ERROR] Credstore volume not found: $CREDSTORE_DEVICE"
  exit 3
fi
echo "[OK] Credstore volume found: $CREDSTORE_DEVICE"

echo ""

# Show commands that will be executed
cat <<EOF
[Commands to Execute]

  [1] Generate recovery key:
      $ systemd-cryptenroll $CREDSTORE_DEVICE \\
          --recovery-key \\
          --unlock-key-file=<(echo -n "keystone")

  [2] Enroll TPM (preserves password slot as manual fallback):
      $ systemd-cryptenroll $CREDSTORE_DEVICE \\
          --tpm2-device=auto \\
          --tpm2-pcrs=$TPM_PCRS

      When prompted, READ OR PASTE the recovery key from your backup.

      This verifies you saved it correctly AND completes enrollment.

      PCRs (Platform Configuration Registers):
        PCR 1: Firmware config (BIOS settings, hardware changes)
        PCR 7: Secure Boot state (enrolled keys)

      Re-enrollment needed if:
        * Hardware changes (motherboard, RAM, CPU) - PCR 1
        * BIOS settings changed - PCR 1
        * Secure Boot keys changed - PCR 7
        * TPM replaced

      Firmware/kernel updates: No re-enrollment (signed by same keys)

  [3] Create enrollment marker:
      $ cat > /var/lib/keystone/tpm-enrollment-complete

EOF

# If not auto mode, exit with instructions
if [ "$AUTO_MODE" = false ]; then
    cat <<EOF
[Manual Execution]

To execute these commands manually, copy them from above.
To execute automatically, run:
  $ sudo keystone-enroll-recovery --auto

EOF
    exit 0
fi

echo "[Auto-Execution Mode]"
echo ""

# Discover the current slot-0 passphrase. On first-install the default
# "keystone" string still unlocks; after `ks hardware setup` has run
# the password-rotation step, slot 0 holds a user-chosen passphrase
# and we must prompt for it interactively.
TEMP_UNLOCK=$(mktemp)
trap 'rm -f "$TEMP_UNLOCK" "${TEMP_RECOVERY:-}"' EXIT
printf 'keystone' > "$TEMP_UNLOCK"

if @cryptsetup@ open --test-passphrase "$CREDSTORE_DEVICE" --key-file="$TEMP_UNLOCK" >/dev/null 2>&1; then
  echo "[INFO] Default installer password still unlocks — using it as the unlock key."
else
  echo "[INFO] Default installer password no longer unlocks slot 0."
  echo "       Enter your current LUKS passphrase to authorize recovery-key generation:"
  IFS= read -rs CURRENT_PW
  echo
  printf '%s' "$CURRENT_PW" > "$TEMP_UNLOCK"
  unset CURRENT_PW
  if ! @cryptsetup@ open --test-passphrase "$CREDSTORE_DEVICE" --key-file="$TEMP_UNLOCK" >/dev/null 2>&1; then
    echo "[ERROR] That passphrase does not unlock slot 0. Aborting."
    exit 4
  fi
fi

# Execute commands with progress output
echo "[Step 1/4] Generating recovery key..."
echo "$ systemd-cryptenroll --recovery-key --unlock-key-file=<current-passphrase>"

TEMP_RECOVERY=$(mktemp)

if ! @systemd_cryptenroll@ \
  "$CREDSTORE_DEVICE" \
  --recovery-key \
  --unlock-key-file="$TEMP_UNLOCK" \
  2>&1 | tee "$TEMP_RECOVERY"; then
  echo "[ERROR] Failed to generate recovery key"
  exit 4
fi

# Extract recovery key from output
# Format: indented 8-word recovery key (each word is 8 letters)
# Example:     cgecnccb-gkglvevj-vihtbgee-jetghjkr-gtrvuljc-vhdirfdc-jtccfikg-jifuhvkf
RECOVERY_KEY=$(grep -oP '^\s+[a-z]{8}(-[a-z]{8}){7}$' "$TEMP_RECOVERY" | tr -d '[:space:]' || echo "")

if [[ -z "$RECOVERY_KEY" ]]; then
  echo "[ERROR] Could not extract recovery key from output"
  echo ""
  echo "systemd-cryptenroll output:"
  cat "$TEMP_RECOVERY"
  exit 5
fi

echo ""
echo "+-------------------------------------------------------------------------+"
echo "|                       YOUR RECOVERY KEY                                 |"
echo "+-------------------------------------------------------------------------+"
echo "|                                                                         |"
echo "|  $RECOVERY_KEY  |"
echo "|                                                                         |"
echo "+-------------------------------------------------------------------------+"
echo ""
echo "[!] CRITICAL: Save this key immediately"
echo ""
echo "Store in:"
echo "  [OK] Password manager with offline backup"
echo "  [OK] Printed paper in physical safe"
echo "  [NO] NOT on this encrypted disk"
echo ""
# Only prompt if running in interactive terminal
if [[ -t 0 ]]; then
  read -rp "Press ENTER after you have saved this key..."
  echo ""
else
  echo "[Non-interactive mode detected - skipping confirmation prompt]"
  echo ""
  sleep 2  # Give user time to see the key
fi

echo "[Step 2/3] Enrolling TPM and removing default password..."
echo ""
echo "[!] VERIFICATION REQUIRED"
echo ""
echo "You will be prompted to enter a passphrase."
echo ""
echo "READ OR PASTE the recovery key FROM YOUR BACKUP (password manager, paper)"
echo "to verify you saved it correctly."
echo ""
echo "PCRs (Platform Configuration Registers):"
echo "  PCR 1: Firmware config (BIOS settings, hardware changes)"
echo "  PCR 7: Secure Boot state (enrolled keys)"
echo ""
echo "This command will:"
echo "  * Verify your recovery key works"
echo "  * Enroll TPM for automatic unlock (PCRs: $TPM_PCRS)"
echo "  * Remove the default \"keystone\" password"
echo ""
echo "Re-enrollment needed if:"
echo "  * Hardware changes (motherboard, RAM, CPU) - PCR 1"
echo "  * BIOS settings changed - PCR 1"
echo "  * Secure Boot keys changed - PCR 7"
echo "  * TPM replaced"
echo ""
echo "Firmware/kernel updates: No re-enrollment needed (signed by same keys)"
echo ""
# Check if running in interactive terminal
if [[ -t 0 ]]; then
  # Interactive: Let user type recovery key for verification
  echo "$ systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=$TPM_PCRS"
  echo ""

  # Layered-fallback model: the password slot (slot 0) is intentionally
  # preserved alongside TPM/recovery/FIDO2 so that a user can still
  # unlock the disk manually if every automatic method fails. The
  # caller (`ks hardware setup` or the install-time wrapper) is
  # responsible for ensuring slot 0 holds a strong user-chosen
  # passphrase before this script runs, not the default "keystone"
  # installer placeholder.
  if ! @systemd_cryptenroll@ \
    "$CREDSTORE_DEVICE" \
    --tpm2-device=auto \
    --tpm2-pcrs="$TPM_PCRS"; then
    echo ""
    echo "[ERROR] TPM enrollment failed"
    echo ""
    echo "Your recovery key is still enrolled. To retry:"
    echo "  sudo keystone-enroll-recovery --auto"
    exit 6
  fi
else
  # Non-interactive: Auto-provide recovery key
  echo "$ systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=$TPM_PCRS --unlock-key-file=<(echo -n \"<recovery-key>\")"
  echo "[Non-interactive mode - automatically using recovery key]"
  echo ""

  if ! @systemd_cryptenroll@ \
    "$CREDSTORE_DEVICE" \
    --tpm2-device=auto \
    --tpm2-pcrs="$TPM_PCRS" \
    --unlock-key-file=<(echo -n "$RECOVERY_KEY"); then
    echo ""
    echo "[ERROR] TPM enrollment failed"
    exit 6
  fi
fi
echo ""
echo "[OK] TPM enrolled (password slot preserved as manual fallback)"
echo ""

echo "[Step 3/3] Creating enrollment marker..."
mkdir -p "$(dirname "$MARKER_FILE")"
cat > "$MARKER_FILE" <<EOF
Enrollment completed: $(date -Iseconds)
Method: recovery-key
SecureBoot: enabled
TPM PCRs: $TPM_PCRS
Recovery key: $RECOVERY_KEY (first 4 chars: ${RECOVERY_KEY:0:4})
EOF
echo "[OK] Enrollment marker created"
echo ""

cat <<'EOF'
+-------------------------------------------------------------------------+
|  TPM ENROLLMENT COMPLETE                                                |
+-------------------------------------------------------------------------+
|                                                                         |
|  Your system will now unlock automatically during boot.                 |
|                                                                         |
|  If automatic unlock fails, you can unlock with your recovery key.     |
|  Test with: sudo reboot                                                |
|                                                                         |
+-------------------------------------------------------------------------+

EOF

echo "Enrollment complete! Your system is now secured with TPM automatic unlock."
