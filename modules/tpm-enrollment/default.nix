{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.tpmEnrollment;

  # T010: Convert PCR list to comma-separated string for systemd-cryptenroll
  # Example: [1 7] -> "1,7"
  tpmPCRString = lib.concatStringsSep "," (map toString cfg.tpmPCRs);

  # Helper to create executable substituted scripts
  makeExecutableScript = name: src: substitutions:
    pkgs.runCommand name {} ''
      cp ${pkgs.substituteAll ({
          inherit src;
        }
        // substitutions)} $out
      chmod +x $out
    '';

  # Enrollment check script with substitutions
  enrollmentCheckScript = makeExecutableScript "enrollment-check.sh" ./enrollment-check.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    credstoreDevice = cfg.credstoreDevice;
  };
in {
  # T006: Module options with enable
  # T007: Add tpmPCRs and credstoreDevice options
  options.keystone.tpmEnrollment = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable TPM-based disk encryption enrollment.

        When enabled, provides enrollment commands and login banner notification
        for systems that have not yet configured TPM automatic unlock.

        Defaults to true when secureBoot and disko are enabled.
      '';
    };

    tpmPCRs = mkOption {
      type = types.listOf types.int;
      default = [1 7];
      example = [7];
      description = ''
        List of TPM Platform Configuration Registers (PCRs) to bind disk unlock to.

        Default [1 7] binds to:
        - PCR 1: Firmware configuration
        - PCR 7: Secure Boot certificates and policies

        Common alternatives:
        - [7]: Secure Boot only (more update-resilient, recommended for frequent firmware updates)
        - [0 1 7]: Firmware code + config + Secure Boot (more restrictive)
        - [7 11]: Secure Boot + kernel UKI (requires signed PCR policies)

        Changes to bound PCRs will cause automatic unlock to fail, requiring
        recovery key or custom password until TPM is re-enrolled.
      '';
    };

    credstoreDevice = mkOption {
      type = types.str;
      default = "/dev/zvol/rpool/credstore";
      example = "/dev/zvol/rpool/credstore";
      description = ''
        Path to the LUKS-encrypted credstore volume.

        This must match the credstore device created by the disko module.
        The default path assumes the standard Keystone disko configuration.
      '';
    };
  };

  # T008: Assertions for dependencies
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.keystone.secureBoot.enable or false;
        message = ''
          TPM enrollment requires Secure Boot to be enabled.
          Set: keystone.secureBoot.enable = true;
        '';
      }
      {
        assertion = config.keystone.disko.enable or false;
        message = ''
          TPM enrollment requires disko credstore volume.
          Set: keystone.disko.enable = true;
        '';
      }
      {
        assertion = (length cfg.tpmPCRs) > 0;
        message = ''
          TPM enrollment requires at least one PCR to bind to.
          The tpmPCRs list cannot be empty.
        '';
      }
      {
        assertion = all (pcr: pcr >= 0 && pcr <= 23) cfg.tpmPCRs;
        message = ''
          TPM PCR values must be in the range 0-23.
          Invalid PCRs in tpmPCRs list: ${toString (filter (pcr: pcr < 0 || pcr > 23) cfg.tpmPCRs)}
        '';
      }
    ];

    # T009: Create /var/lib/keystone directory for state tracking
    systemd.tmpfiles.rules = [
      "d /var/lib/keystone 0755 root root -"
    ];

    # T016: Interactive shell initialization for login banner
    # This runs automatically for all interactive shells (including SSH sessions)
    # NixOS handles the PS1 check internally - only runs for interactive shells
    environment.interactiveShellInit = ''
      # Execute TPM enrollment status check and display banner if needed
      ${pkgs.bash}/bin/bash ${enrollmentCheckScript}
    '';

    # Enrollment command scripts (using executable substituted scripts)
    environment.systemPackages = let
      # Create substituted scripts with proper execute permissions
      enrollRecoveryScript = makeExecutableScript "enroll-recovery.sh" ./enroll-recovery.sh {
        cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
        systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
        bootctl = "${pkgs.systemd}/bin/bootctl";
        credstoreDevice = cfg.credstoreDevice;
        tpmPCRs = tpmPCRString;
      };

      enrollPasswordScript = makeExecutableScript "enroll-password.sh" ./enroll-password.sh {
        cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
        systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
        bootctl = "${pkgs.systemd}/bin/bootctl";
        credstoreDevice = cfg.credstoreDevice;
        tpmPCRs = tpmPCRString;
      };

      enrollTpmScript = makeExecutableScript "enroll-tpm.sh" ./enroll-tpm.sh {
        cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
        systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
        bootctl = "${pkgs.systemd}/bin/bootctl";
        credstoreDevice = cfg.credstoreDevice;
        tpmPCRs = tpmPCRString;
      };
    in [
      # T017-T023: Recovery key enrollment command
      (pkgs.writeShellScriptBin "keystone-enroll-recovery" ''
        exec ${enrollRecoveryScript} "$@"
      '')

      # T024-T029: Custom password enrollment command
      (pkgs.writeShellScriptBin "keystone-enroll-password" ''
        exec ${enrollPasswordScript} "$@"
      '')

      # T030-T035: Standalone TPM enrollment command (advanced users)
      (pkgs.writeShellScriptBin "keystone-enroll-tpm" ''
        exec ${enrollTpmScript} "$@"
      '')
    ];
  };
}
