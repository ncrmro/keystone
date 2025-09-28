{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.client.desktop.hyprland;
in {
  options.keystone.client.desktop.hyprland = {
    enable = mkEnableOption "Hyprland Wayland compositor";
  };

  config = mkIf cfg.enable {
    # Enable Hyprland with UWSM (Universal Wayland Session Manager)
    programs.hyprland = {
      enable = true;
      withUWSM = true;
      # Use stable nixpkgs version to avoid Qt version mismatches
      portalPackage = pkgs.xdg-desktop-portal-hyprland;
    };

    # Enable XDG desktop portal for Wayland
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
    };

    # Enable polkit for authentication dialogs
    security.polkit.enable = true;

    # Wayland environment variables
    environment.sessionVariables = {
      # Hint electron apps to use Wayland
      NIXOS_OZONE_WL = "1";
      # Set default Wayland backend
      GDK_BACKEND = "wayland,x11";
      QT_QPA_PLATFORM = "wayland;xcb";
      SDL_VIDEODRIVER = "wayland";
      CLUTTER_BACKEND = "wayland";
    };

    # Enable required services for Wayland
    services.dbus.enable = true;

    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      # Core Wayland utilities
      wayland
      wayland-protocols
      wayland-utils

      # XWayland for X11 app compatibility
      xwayland
    ];
  };
}
