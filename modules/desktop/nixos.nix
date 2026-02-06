{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  options.keystone.desktop = {
    enable = mkEnableOption "Keystone Desktop - Core desktop packages and utilities";

    user = mkOption {
      type = types.str;
      description = "User for auto-login to Hyprland session";
    };

    hyprland = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Hyprland window manager";
      };
    };

    greetd = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Greetd display manager";
      };
    };

    audio = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Pipewire audio stack";
      };
    };

    bluetooth = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Bluetooth support";
      };
    };

    networking = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NetworkManager and systemd-resolved for laptops, portables, and thin clients";
      };
    };
  };

  config = mkIf cfg.enable {
    # Hyprland with UWSM (using official flake for latest features)
    programs.hyprland = mkIf cfg.hyprland.enable {
      enable = mkDefault true;
      withUWSM = mkDefault true;
      package = mkDefault inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage = mkDefault pkgs.xdg-desktop-portal-hyprland; # Use stable nixpkgs version to fix Qt version mismatch
    };

    # Greetd display manager with auto-login to hyprlock
    services.greetd = mkIf cfg.greetd.enable {
      enable = mkDefault true;
      settings.default_session = {
        command = mkDefault "uwsm start -F Hyprland";
        user = cfg.user;
      };
    };

    # Configure PAM to register greetd session as wayland type
    # This enables loginctl lock-session to work properly
    security.pam.services.greetd.rules.session.systemd.settings = mkIf cfg.greetd.enable {
      type = "wayland";
      # Setting the session class to 'user' explicitly tells logind that this is a regular user session,
      # which enables proper lock screen support. Without this, logind might classify the session
      # as a 'greeter' (login screen), preventing 'loginctl lock-session' from working.
      class = "user";
    };

    # Pipewire audio stack
    security.rtkit.enable = mkIf cfg.audio.enable (mkDefault true);
    services.pulseaudio.enable = mkIf cfg.audio.enable (mkDefault false);
    services.pipewire = mkIf cfg.audio.enable {
      enable = mkDefault true;
      alsa.enable = mkDefault true;
      pulse.enable = mkDefault true;
      jack.enable = mkDefault true;
    };

    # Bluetooth
    hardware.bluetooth.enable = mkIf cfg.bluetooth.enable (mkDefault true);
    services.blueman.enable = mkIf cfg.bluetooth.enable (mkDefault true);

    # Printing (CUPS + Avahi/mDNS discovery)
    services.printing.enable = mkDefault true;
    services.avahi = {
      enable = mkDefault true;
      nssmdns4 = mkDefault true;
      openFirewall = mkDefault true;
    };

    # Networking (for laptops, portables, and thin clients)
    networking.networkmanager.enable = mkIf cfg.networking.enable (mkDefault true);
    services.resolved.enable = mkIf cfg.networking.enable (mkDefault true);
    # Required for Tailscale MagicDNS to work with systemd-resolved
    # https://github.com/NixOS/nixpkgs/issues/231191#issuecomment-1664053176
    environment.etc."resolv.conf".mode = mkIf cfg.networking.enable "direct-symlink";

    # Fonts
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
    ];

    # System packages for desktop environment
    environment.systemPackages = with pkgs; [
      # Screen recording
      gpu-screen-recorder

      # Media
      ## Video Editor
      ## kdenlive disabled: broken in nixpkgs unstable (missing shaderc link in ffmpeg-full)
      # kdePackages.kdenlive
      ## Video Player
      mpv

      # File management
      nautilus
      file-roller

      # System utilities
      pavucontrol
      networkmanagerapplet
      blueberry

      # XDG portals and desktop integration
      xdg-utils
      xdg-user-dirs

      # Polkit agent
      hyprpolkitagent

      # Cursor themes
      adwaita-icon-theme

      # Additional Hyprland tools
      hyprsunset
      hyprlock
      hypridle
      hyprpaper
    ];

    # Enable polkit
    security.polkit.enable = mkDefault true;

    # XDG portal configuration
    xdg.portal = {
      enable = mkDefault true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };

    # This allows shell scripts to resolve /bin/bash
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    ];

    # OOM Killer configuration
    # Prioritize killing docker/podman rootless processes over Hyprland
    systemd.user.services = {
      docker.serviceConfig.OOMScoreAdjust = 1000;
      podman.serviceConfig.OOMScoreAdjust = 1000;
      "wayland-wm@Hyprland".serviceConfig.OOMScoreAdjust = -500;
    };
  };
}
