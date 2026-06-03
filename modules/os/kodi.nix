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
    enable = mkEnableOption "Kodi media center kiosk (GBM/KMS, auto-starts on a VT at boot)";

    user = mkOption {
      type = types.str;
      default = "kodi";
      description = "User account Kodi runs as. Created as a system user if it does not already exist.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.kodi-gbm;
      defaultText = literalExpression "pkgs.kodi-gbm";
      description = ''
        Kodi package to use. Must be a GBM build: Kodi renders directly on
        KMS/DRM with no Wayland compositor in the path. This is the most robust
        kiosk path on Raspberry Pi and inside VMs — a compositor (cage/wlroots)
        is the usual source of black-screen-on-boot when GPU acceleration is
        absent or the virtio-gpu hardware cursor is broken.
      '';
    };

    tty = mkOption {
      type = types.str;
      default = "tty1";
      description = "Virtual terminal Kodi takes over. getty/autovt on this VT is disabled so Kodi owns it.";
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
        "render"
        "input"
        "tty"
      ]
      ++ optional cfg.cec.enable "dialout";
      description = "Kodi kiosk user";
    };
    users.groups.${cfg.user} = mkDefault { };

    environment.systemPackages = [ cfg.package ] ++ optionals cfg.cec.enable [ pkgs.libcec ];

    hardware.graphics.enable = true;
    # Kodi needs a running PipeWire/PulseAudio for audio; assume the host enables one.
    # CRITICAL: do not enable sound here — conflicts with host-level audio stack choice.

    # Kodi GBM talks straight to KMS/DRM. Running it on a real VT through the
    # "login" PAM stack gives logind a class=user session on seat0, whose ACLs
    # grant the /dev/dri (DRM master) and /dev/input access GBM/EGL needs.
    systemd.services.kodi = {
      description = "Kodi media center (GBM kiosk)";
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
        "sound.target"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = true;
      serviceConfig = {
        User = cfg.user;
        Group = cfg.user;
        PAMName = "login";
        TTYPath = "/dev/${cfg.tty}";
        StandardInput = "tty";
        StandardOutput = "journal";
        StandardError = "journal";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        UtmpIdentifier = cfg.tty;
        UtmpMode = "user";
        WorkingDirectory = "/var/lib/kodi";
        ExecStart = "${cfg.package}/bin/kodi-standalone";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Don't let getty race Kodi for the VT it owns.
    systemd.services."getty@${cfg.tty}".enable = false;
    systemd.services."autovt@${cfg.tty}".enable = false;

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        8080 # web interface
        9090 # JSON-RPC websocket
        9777 # event server
      ];
      allowedUDPPorts = [
        1900 # SSDP / UPnP
        5353 # mDNS (Avahi service discovery)
        9777
      ];
    };

    services.avahi = {
      enable = true;
      openFirewall = mkDefault cfg.openFirewall;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };
}
