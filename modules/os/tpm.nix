# Keystone OS TPM Module
#
# Handles TPM-based disk encryption enrollment and automatic unlock.
# Provides enrollment commands and status checking.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.tpm;

  # Convert PCR list to comma-separated string for systemd-cryptenroll
  tpmPCRString = lib.concatStringsSep "," (map toString cfg.pcrs);

  # Credstore device path (always ZFS zvol when using ZFS storage)
  credstoreDevice =
    if osCfg.storage.type == "zfs" then
      "/dev/zvol/rpool/credstore"
    else
      "/dev/disk/by-partlabel/disk-root-root";

  # All disk-unlock enrollment goes through `ks hardware setup` and the
  # per-method `ks hardware enroll <method>` primitives in
  # `packages/ks/src/cmd/hardware/enroll.rs`. The keystone-tpm-check
  # systemd service below is the only inline shell that remains; it
  # writes the world-readable disk-unlock-status.json marker.
  # Some context for the inline script:
  # disk-unlock-status.json marker.
  refreshDiskUnlockStatusScript = pkgs.writeShellScript "refresh-disk-unlock-status.sh" ''
        set -euo pipefail

        STATUS_FILE="/var/lib/keystone/disk-unlock-status.json"
        MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"
        DEVICE="${credstoreDevice}"
        TOKENS="$(${pkgs.cryptsetup}/bin/cryptsetup luksDump "$DEVICE" 2>/dev/null || true)"
        TPM_ENROLLED=false
        FIDO2_ENROLLED=false

        if printf "%s\n" "$TOKENS" | grep -q "systemd-tpm2"; then
          TPM_ENROLLED=true
        fi

        if printf "%s\n" "$TOKENS" | grep -q "systemd-fido2"; then
          FIDO2_ENROLLED=true
        fi

        mkdir -p /var/lib/keystone

        if [ "$TPM_ENROLLED" = true ]; then
          cat > "$MARKER_FILE" <<MARKER
    TPM enrollment verified: $(date -Iseconds)
    Device: ${credstoreDevice}
    MARKER
        else
          rm -f "$MARKER_FILE"
        fi

        cat > "$STATUS_FILE" <<EOF
    {
      "checked_at": "$(date -Iseconds)",
      "device": "${credstoreDevice}",
      "tpm_enrolled": $TPM_ENROLLED,
      "fido2_enrolled": $FIDO2_ENROLLED
    }
    EOF
        chmod 0644 "$STATUS_FILE"
  '';
in
{
  config = mkIf (osCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = length cfg.pcrs > 0;
        message = "TPM enrollment requires at least one PCR to bind to";
      }
      {
        assertion = all (pcr: pcr >= 0 && pcr <= 23) cfg.pcrs;
        message = "TPM PCR values must be in the range 0-23";
      }
    ];

    # Create state directory for tracking
    systemd.tmpfiles.rules = [
      "d /var/lib/keystone 0755 root root -"
    ];

    # Boot-time check: inspect LUKS header as root and maintain marker file.
    # Regular users cannot read block devices, so this must run as a systemd
    # service rather than in interactiveShellInit.
    systemd.services.keystone-tpm-check = {
      description = "Check disk unlock enrollment status and update marker files";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.cryptsetup ];
      script = ''
        exec ${refreshDiskUnlockStatusScript}
      '';
    };

    # Register TPM enrollment notification via the keystone notification system.
    # The keystone-tpm-check service writes the marker file when TPM is enrolled;
    # the notification is suppressed automatically once enrollment is complete.
    keystone.os.notifications.items = [
      {
        id = "tpm-enrollment";
        title = "TPM Enrollment Required";
        body = ''
          +--------------------------------------------------------------------------+
          | [!] WARNING: HARDWARE ENROLLMENT NOT CONFIGURED                          |
          +--------------------------------------------------------------------------+
          |                                                                          |
          | TPM auto-unlock has not yet been enrolled on this system. Without       |
          | TPM enrollment, you will need to enter your LUKS passphrase at every    |
          | boot, and the default installer password may still be active.           |
          |                                                                          |
          | To secure your encrypted disk, run the one-shot enrollment:             |
          |                                                                          |
          |      $ ks hardware setup                                                 |
          |                                                                          |
          | This will detect your hardware and chain:                               |
          |   1. Rotate the default password to one you choose                      |
          |   2. Generate a paper recovery key                                      |
          |   3. Enroll TPM2 auto-unlock                                            |
          |   4. Enroll your YubiKey/FIDO2 (if plugged in)                          |
          |   5. Enroll fingerprint reader (if present)                             |
          |                                                                          |
          | See `ks hardware report` for the current credential state.             |
          |                                                                          |
          +--------------------------------------------------------------------------+
        '';
        markerFile = "/var/lib/keystone/tpm-enrollment-complete";
      }
    ];

    # SECURITY: TPM auto-unlock is not active until explicit enrollment
    # via `ks hardware setup` (or the per-method `ks hardware enroll
    # <method>` primitives). The tpm2-device=auto crypttab hint in
    # storage.nix tells systemd-cryptsetup to attempt TPM unlock, but
    # when no TPM token is enrolled in the LUKS header, systemd initrd
    # still asks for the passphrase.
    environment.systemPackages = [
      # Root helper to refresh the world-readable disk unlock status
      # file. Invoked from the keystone-tpm-check systemd service.
      (pkgs.writeShellScriptBin "keystone-refresh-disk-unlock-status" ''
        exec ${refreshDiskUnlockStatusScript}
      '')
    ];
  };
}
