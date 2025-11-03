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

    # Configure lanzaboote for Secure Boot
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    # Disable systemd-boot when using lanzaboote
    boot.loader.systemd-boot.enable = mkForce false;

    # Activation script to provision Secure Boot keys on first boot
    system.activationScripts.secureBootProvisioning = {
      text = ''
        # Run Secure Boot provisioning script
        ${pkgs.bash}/bin/bash ${./provision.sh}
      '';
      deps = []; # Run early in activation
    };
  };
}
