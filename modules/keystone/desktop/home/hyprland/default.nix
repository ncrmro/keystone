{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.hyprland;
  hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
in
{
  imports = [
    ./appearance.nix
    ./autostart.nix
    ./bindings.nix
    ./environment.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./hyprsunset.nix
    ./input.nix
    ./layout.nix
  ];

  options.keystone.desktop.hyprland = {
    enable = mkEnableOption "Hyprland window manager configuration";

    monitors = mkOption {
      type = types.listOf types.str;
      default = [ ",preferred,auto,1" ];
      description = "Monitor configuration strings for Hyprland";
    };

    terminal = mkOption {
      type = types.str;
      default = "uwsm app -- ghostty";
      description = "Default terminal application";
    };

    fileManager = mkOption {
      type = types.str;
      default = "uwsm app -- nautilus --new-window";
      description = "Default file manager application";
    };

    browser = mkOption {
      type = types.str;
      default = "uwsm app -- chromium --new-window --ozone-platform=wayland";
      description = "Default browser application";
    };

    scale = mkOption {
      type = types.int;
      default = 2;
      description = "Display scale factor (1 for 1x displays, 2 for 2x/HiDPI displays)";
    };
  };

  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprlandPkg;
      # Disabled since programs.hyprland.withUWSM is enabled on NixOS
      systemd.enable = false;

      # Source theme file for runtime theme switching
      extraConfig = ''
        source = ~/.config/keystone/current/theme/hyprland.conf
      '';

      settings = {
        # Default applications
        "$terminal" = mkDefault cfg.terminal;
        "$fileManager" = mkDefault cfg.fileManager;
        "$browser" = mkDefault cfg.browser;

        # Monitor configuration
        monitor = mkDefault cfg.monitors;
      };
    };

    # Supporting packages
    home.packages = with pkgs; [
      wofi
      waybar
      libnotify
      wl-clipboard
      wl-clip-persist
      clipse
      grim
      slurp
      brightnessctl
      playerctl
    ];
  };
}
