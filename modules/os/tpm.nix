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
with lib; let
  osCfg = config.keystone.os;
  cfg = osCfg.tpm;

  # Convert PCR list to comma-separated string for systemd-cryptenroll
  tpmPCRString = lib.concatStringsSep "," (map toString cfg.pcrs);

  # Credstore device path (always ZFS zvol when using ZFS storage)
  credstoreDevice =
    if osCfg.storage.type == "zfs"
    then "/dev/zvol/rpool/credstore"
    else "/dev/disk/by-partlabel/disk-root-root";

  # Helper to create executable substituted scripts
  makeExecutableScript = name: src: substitutions:
    pkgs.runCommand name {} ''
      cp ${pkgs.substituteAll ({
          inherit src;
        }
        // substitutions)} $out
      chmod +x $out
    '';

  # Enrollment check script
  enrollmentCheckScript = makeExecutableScript "enrollment-check.sh" ./scripts/enrollment-check.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    inherit credstoreDevice;
  };

  # Recovery key enrollment script
  enrollRecoveryScript = makeExecutableScript "enroll-recovery.sh" ./scripts/enroll-recovery.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    inherit credstoreDevice;
    tpmPCRs = tpmPCRString;
  };

  # Password enrollment script
  enrollPasswordScript = makeExecutableScript "enroll-password.sh" ./scripts/enroll-password.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    inherit credstoreDevice;
    tpmPCRs = tpmPCRString;
  };

  # TPM enrollment script
  enrollTpmScript = makeExecutableScript "enroll-tpm.sh" ./scripts/enroll-tpm.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    inherit credstoreDevice;
    tpmPCRs = tpmPCRString;
  };
in {
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

    # Login banner for enrollment status
    environment.interactiveShellInit = ''
      ${pkgs.bash}/bin/bash ${enrollmentCheckScript}
    '';

    # Enrollment commands
    environment.systemPackages = [
      # Recovery key enrollment
      (pkgs.writeShellScriptBin "keystone-enroll-recovery" ''
        exec ${enrollRecoveryScript} "$@"
      '')

      # Custom password enrollment
      (pkgs.writeShellScriptBin "keystone-enroll-password" ''
        exec ${enrollPasswordScript} "$@"
      '')

      # TPM enrollment (standalone)
      (pkgs.writeShellScriptBin "keystone-enroll-tpm" ''
        exec ${enrollTpmScript} "$@"
      '')
    ];
  };
}
