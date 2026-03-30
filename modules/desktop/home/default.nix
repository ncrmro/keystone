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

    audio = {
      defaults = {
        sink = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Default output device name to apply at desktop session start.";
        };

        source = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Default input device name to apply at desktop session start.";
        };
      };
    };

    printer = {
      default = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default CUPS printer name to apply at desktop session start.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Desktop implies terminal
    keystone.terminal.enable = true;

    # UHK Agent copies firmware docs from the Nix store into ~/.config/uhk-agent.
    # Those source files are read-only, and the app preserves that mode, which
    # breaks later updates when it tries to refresh docs for the current firmware.
    home.activation.keystoneUhkAgentCacheFix = mkIf cfg.uhk.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        uhk_cache_dir="$HOME/.config/uhk-agent/smart-macro-docs"
        if [ -d "$uhk_cache_dir" ]; then
          ${pkgs.findutils}/bin/find "$uhk_cache_dir" -type d -exec ${pkgs.coreutils}/bin/chmod u+rwx {} +
          ${pkgs.findutils}/bin/find "$uhk_cache_dir" -type f -exec ${pkgs.coreutils}/bin/chmod u+rw {} +
        fi
      ''
    );

    home.packages = [
      # Presentations
      pkgs.keystone.slidev
    ]
    ++ optionals cfg.uhk.enable [
      pkgs.uhk-agent
    ];
  };
}
