{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.desktop;
in {
  imports = [
    ./components
    ./hyprland
    ./scripts
    ./theming
    ../../terminal
  ];

  options.keystone.desktop = {
    enable = mkEnableOption "Keystone Desktop - Core desktop packages and utilities for Home Manager";
  };

  config = mkIf cfg.enable {
    # Desktop implies terminal
    keystone.terminal.enable = true;

    home.packages = with pkgs; [
      # Core utilities
    ];
  };
}
