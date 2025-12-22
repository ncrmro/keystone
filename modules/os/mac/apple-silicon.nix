# Keystone OS Mac - Apple Silicon Hardware Support
#
# Configures nixos-apple-silicon hardware support for M1/M2/M3 Macs.
# Includes Asahi Linux drivers and firmware.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
in {
  config = mkIf osCfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "Mac module only supports aarch64-linux (Apple Silicon)";
      }
    ];

    # Import nixos-apple-silicon hardware support
    # This is expected to be provided by the user's flake configuration
    # via: inputs.nixos-apple-silicon.nixosModules.apple-silicon-support
    
    # CRITICAL: Apple Silicon cannot modify EFI variables
    boot.loader.efi.canTouchEfiVariables = false;

    # Peripheral firmware from EFI partition (if using nixos-apple-silicon)
    # This will be set by the nixos-apple-silicon module if available
    # hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
  };
}
