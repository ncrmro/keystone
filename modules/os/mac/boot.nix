# Keystone OS Mac - Boot Configuration
#
# Configures systemd-boot for Apple Silicon Macs.
# No Secure Boot support (uses Apple's boot chain instead).
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
    # Use systemd-boot (no lanzaboote on Mac)
    boot.loader.systemd-boot.enable = true;
    
    # CRITICAL: Apple Silicon cannot modify EFI variables
    boot.loader.efi.canTouchEfiVariables = false;
  };
}
