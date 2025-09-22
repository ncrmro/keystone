inputs: {
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [./hyprland/configuration.nix];
  
  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    systemd.enable = true;
    xwayland.enable = true;
  };
  
  # Enable polkit agent for authentication
  services.hyprpolkitagent.enable = true;
  
  # Enable XDG desktop portal
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
    configPackages = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };
}