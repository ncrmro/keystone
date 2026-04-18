{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.os.services.kodi;
in
{
  options.keystone.os.services.kodi = {
    enable = mkEnableOption "Kodi media center in kiosk mode (auto-login, fullscreen)";

    user = mkOption {
      type = types.str;
      default = "kodi";
      description = "User account Kodi runs as. Created as a system user if it does not already exist.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.kodi-wayland;
      defaultText = literalExpression "pkgs.kodi-wayland";
      description = "Kodi package to use. For headless GBM (no compositor), set to `pkgs.kodi-gbm`.";
    };

    cec.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable HDMI-CEC support so a TV remote can control Kodi. Adds the Kodi user to the `dialout` group for /dev/cec* access.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open ports for Kodi JSON-RPC, web interface, and UPnP/DLNA discovery.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = mkDefault {
      isSystemUser = true;
      createHome = true;
      home = "/var/lib/kodi";
      group = cfg.user;
      extraGroups = [
        "audio"
        "video"
        "input"
      ]
      ++ optional cfg.cec.enable "dialout";
      description = "Kodi kiosk user";
    };
    users.groups.${cfg.user} = mkDefault { };

    environment.systemPackages = [ cfg.package ] ++ optionals cfg.cec.enable [ pkgs.libcec ];

    # Cage is a minimal Wayland kiosk compositor: one fullscreen client, no decorations.
    # Pairs with greetd for passwordless auto-login on tty1.
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.cage}/bin/cage -s -- ${cfg.package}/bin/kodi-standalone";
        user = cfg.user;
      };
    };

    hardware.graphics.enable = true;
    # Kodi needs a running PipeWire/PulseAudio for audio; assume the host enables one.
    # CRITICAL: do not enable sound here — conflicts with host-level audio stack choice.

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        8080 # web interface
        9090 # JSON-RPC websocket
        9777 # event server
      ];
      allowedUDPPorts = [
        1900 # SSDP / UPnP
        9777
      ];
    };

    services.avahi = {
      enable = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };
}
