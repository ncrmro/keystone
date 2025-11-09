{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.client.services.networking;
in {
  options.keystone.client.services.networking = {
    enable =
      mkEnableOption "NetworkManager and network services"
      // {
        default = true;
      };

    bluetooth.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Bluetooth support";
    };
  };

  config = mkIf cfg.enable {
    # Enable NetworkManager for network management
    networking.networkmanager.enable = true;

    # Enable systemd-resolved for DNS
    services.resolved.enable = true;

    # Enable mDNS for service discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
    };

    # Bluetooth configuration
    hardware.bluetooth = mkIf cfg.bluetooth.enable {
      enable = true;
      powerOnBoot = true;
    };

    # Bluetooth GUI manager
    services.blueman.enable = mkIf cfg.bluetooth.enable true;

    # Add user to networkmanager group (will be configured per user)
    # This allows non-root users to manage network connections
    users.groups.networkmanager = {};

    # Essential networking packages
    environment.systemPackages = with pkgs;
      [
        # Network utilities
        networkmanagerapplet # GUI for NetworkManager

        # Bluetooth GUI (if enabled)
      ]
      ++ optionals cfg.bluetooth.enable [
        blueberry # Bluetooth configuration GUI
      ];
  };
}
