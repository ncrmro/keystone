{ config, lib, pkgs, omarchy, ... }:

let
  cfg = config.programs.omarchy-theming;
in
{
  meta.maintainers = [ ];

  imports = [
    ./binaries.nix
    ./activation.nix
    ./terminal.nix
    ./desktop.nix
  ];

  options.programs.omarchy-theming = {
    enable = lib.mkEnableOption "Omarchy theming system" // {
      description = ''
        Whether to enable the Omarchy theming system for unified visual
        styling across terminal and desktop applications.

        When enabled, this module:
        - Installs Omarchy theme management binaries
        - Sets up default theme in ~/.config/omarchy/themes/default/
        - Creates initial symlink to active theme
        - Configures supported applications to use themes

        Theme selection persists across system rebuilds. Use the
        omarchy-theme-next and omarchy-theme-set commands to change
        active theme after initial setup.
      '';
      default = false;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = omarchy;
      description = ''
        The Omarchy package to use as the source for themes and binaries.

        Override this if you want to:
        - Use a forked version of Omarchy
        - Pin to a specific Omarchy version
        - Test local Omarchy modifications

        The package must provide:
        - bin/ directory with theme management scripts
        - themes/ directory with at least a default theme
        - logo.txt file
      '';
      example = lib.literalExpression "pkgs.omarchy.override { ... }";
    };

    terminal = {
      enable = lib.mkEnableOption "terminal application theming" // {
        description = ''
          Enable theming for terminal applications (Helix, Ghostty).

          When enabled, supported terminal applications are configured to
          load theme settings from ~/.config/omarchy/current/theme/.

          Applications gracefully degrade if theme files are missing.
        '';
        default = true;
      };

      applications = {
        helix = lib.mkEnableOption "Helix editor theming" // {
          description = ''
            Configure Helix editor to use Omarchy theme.

            Requires programs.terminal-dev-environment.tools.editor to be enabled.
            Theme configuration is loaded from omarchy/current/theme/helix.toml.
          '';
          default = true;
        };

        ghostty = lib.mkEnableOption "Ghostty terminal theming" // {
          description = ''
            Configure Ghostty terminal to use Omarchy theme.

            Requires programs.terminal-dev-environment.tools.terminal to be enabled.
            Theme configuration is loaded from omarchy/current/theme/ghostty.conf
            via Ghostty's config-file directive.
          '';
          default = true;
        };
      };
    };

    desktop = {
      enable = lib.mkEnableOption "desktop environment theming (Hyprland)" // {
        description = ''
          Enable desktop environment theming (STUB - NOT YET IMPLEMENTED).

          This option can be enabled without breaking the system, but does not
          currently apply theming to Hyprland, waybar, or other desktop components.

          When enabled, it exposes the OMARCHY_THEME_PATH environment variable
          for manual integration.

          Full Hyprland theming will be implemented in a future iteration.
        '';
        default = false;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Install default theme files
    home.file = {
      "${config.xdg.configHome}/omarchy/themes/default" = {
        source = "${cfg.package}/themes/default";
        recursive = true;
      };
      
      "${config.home.homeDirectory}/.local/share/omarchy/logo.txt" = {
        source = "${cfg.package}/logo.txt";
      };
    };

    # Assertions for configuration validation
    assertions = [
      {
        assertion = cfg.terminal.enable -> cfg.terminal.applications.helix || cfg.terminal.applications.ghostty;
        message = "At least one terminal application must be enabled when terminal theming is enabled";
      }
    ];

    # Warnings for potentially misconfigured setups
    warnings = 
      lib.optionals (cfg.terminal.enable && (config.programs.terminal-dev-environment.enable or false) == false) [
        "Terminal theming is enabled but programs.terminal-dev-environment is not enabled. Theme integration may not work as expected."
      ]
      ++ lib.optionals (cfg.terminal.enable && cfg.terminal.applications.helix && (config.programs.terminal-dev-environment.tools.editor or false) == false) [
        "Helix theming is enabled but programs.terminal-dev-environment.tools.editor is not enabled. Helix theme will not be applied."
      ]
      ++ lib.optionals (cfg.terminal.enable && cfg.terminal.applications.ghostty && (config.programs.terminal-dev-environment.tools.terminal or false) == false) [
        "Ghostty theming is enabled but programs.terminal-dev-environment.tools.terminal is not enabled. Ghostty theme will not be applied."
      ];
  };
}
