# Keystone OS Base - Locale Configuration Module
#
# Platform-agnostic locale settings.
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
    # Locale defaults
    time.timeZone = lib.mkDefault "UTC";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  };
}
