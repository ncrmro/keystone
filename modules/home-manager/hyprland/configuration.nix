{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.keystone;
in {
  imports = [
    ./autostart.nix
    ./bindings.nix
    ./envs.nix
    ./input.nix
    ./looknfeel.nix
    ./windows.nix
  ];
  
  wayland.windowManager.hyprland.settings = {
    # Default applications
    "$terminal" = lib.mkDefault "alacritty";
    "$fileManager" = lib.mkDefault "nautilus";
    "$browser" = lib.mkDefault "firefox";
    "$menu" = lib.mkDefault "walker";
    
    # Monitor configuration - use keystone config if available
    monitor = lib.mkDefault (
      if cfg ? desktop && cfg.desktop ? monitors
      then cfg.desktop.monitors
      else [ ",preferred,auto,auto" ]
    );
  };
}