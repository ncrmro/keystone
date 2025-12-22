# Keystone OS Base - Nix Configuration Module
#
# Platform-agnostic Nix settings (flakes, garbage collection).
# Shared by both x86 and Mac modules.
#
{
  lib,
  config,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
in {
  config = mkIf osCfg.enable {
    # Enable flakes if configured
    nix.settings.experimental-features = mkIf osCfg.nix.flakes ["nix-command" "flakes"];

    # Automatic garbage collection
    nix.gc = mkIf osCfg.nix.gc.automatic {
      automatic = true;
      dates = osCfg.nix.gc.dates;
      options = osCfg.nix.gc.options;
    };
  };
}
