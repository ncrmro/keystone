{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.secureBoot;
in {
  options.keystone.secureBoot = {
    enable = mkEnableOption "Secure Boot with lanzaboote";

    includeMS = mkOption {
      type = types.bool;
      default = false;
      description = "Include Microsoft certificates (for dual-boot or hardware compatibility)";
    };

    autoEnroll = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically enroll keys when in Setup Mode";
    };

    pkiBundle = mkOption {
      type = types.str;
      default = "/var/lib/sbctl";
      description = "Path to PKI bundle directory";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.loader.systemd-boot.enable;
        message = "Secure Boot requires systemd-boot to be enabled";
      }
      {
        assertion = config.boot.loader.efi.canTouchEfiVariables;
        message = "Secure Boot requires EFI variables access (boot.loader.efi.canTouchEfiVariables)";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "Secure Boot module currently only supports x86_64-linux";
      }
    ];

    # Ensure sbctl is available in the system
    environment.systemPackages = [pkgs.sbctl];

    # Configuration will be implemented in subsequent tasks
  };
}
