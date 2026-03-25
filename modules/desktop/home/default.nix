{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  imports = [
    ./components
    ./hyprland
    ./scripts
    ./theming
    ../../terminal
  ];

  options.keystone.desktop = {
    enable = mkEnableOption "Keystone Desktop - Core desktop packages and utilities for Home Manager";

    uhk = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Install the Ultimate Hacking Keyboard agent";
      };
    };
  };

  config = mkIf cfg.enable {
    # Desktop implies terminal
    keystone.terminal.enable = true;

    home.packages = [
      # Presentations
      pkgs.keystone.slidev
    ]
    ++ optionals cfg.uhk.enable [
      pkgs.uhk-agent
    ];
  };
}
