# Keystone OS Base - Services Configuration Module
#
# Platform-agnostic system services (Avahi, firewall, DNS).
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
    # Avahi/mDNS configuration
    services.avahi = mkIf osCfg.services.avahi.enable {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
    };

    # Firewall configuration
    networking.firewall.enable = osCfg.services.firewall.enable;

    # DNS resolution
    services.resolved.enable = osCfg.services.resolved.enable;
  };
}
