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
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
  };
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
        command = mkDefault "uwsm start -S -F Hyprland";
        user = cfg.user;
      };
    };

    # Configure PAM to register greetd session as wayland type
    # This enables loginctl lock-session to work properly
    security.pam.services.greetd.rules.session.systemd.settings = mkIf cfg.greetd.enable {
      type = "wayland";
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

    # Fonts
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
    ];

    # System packages for desktop environment
    environment.systemPackages = with pkgs; [
      # Screen recording
      gpu-screen-recorder

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

      # Additional Hyprland tools (from unstable)
      pkgs-unstable.hyprsunset
      pkgs-unstable.hyprlock
      pkgs-unstable.hypridle
      pkgs-unstable.hyprpaper
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
  };
}
