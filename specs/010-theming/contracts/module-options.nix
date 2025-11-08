# Module Options Contract: Dynamic Theming System
#
# This file documents the public API for the omarchy-theming module.
# It serves as a contract for external consumers and implementation guide for developers.
#
# NOTE: This is a DOCUMENTATION file, not an executable Nix expression.
# The actual implementation will live in home-manager/modules/omarchy-theming/

{ config, lib, pkgs, ... }:

{
  # ==================================================================
  # PUBLIC API - These options are stable and supported
  # ==================================================================

  options.programs.omarchy-theming = {

    # ------------------------------------------------------------
    # Core Enable Option
    # ------------------------------------------------------------

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
      example = true;
      default = false;
    };

    # ------------------------------------------------------------
    # Package Source Override
    # ------------------------------------------------------------

    package = lib.mkOption {
      type = lib.types.package;
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
      # Default set in config section to reference flake input
    };

    # ------------------------------------------------------------
    # Terminal Application Theming
    # ------------------------------------------------------------

    terminal = {
      enable = lib.mkEnableOption "terminal application theming" // {
        description = ''
          Enable theming for terminal applications (Helix, Ghostty).

          When enabled, supported terminal applications are configured to
          load theme settings from ~/.config/omarchy/current/theme/.

          Applications gracefully degrade if theme files are missing.
        '';
        default = true;
        example = true;
      };

      applications = {
        helix = lib.mkEnableOption "Helix editor theming" // {
          description = ''
            Configure Helix editor to use Omarchy theme.

            Requires programs.terminal-dev-environment.tools.editor to be enabled.
            Theme configuration is loaded from omarchy/current/theme/helix.toml.
          '';
          default = true;
          example = true;
        };

        ghostty = lib.mkEnableOption "Ghostty terminal theming" // {
          description = ''
            Configure Ghostty terminal to use Omarchy theme.

            Requires programs.terminal-dev-environment.tools.terminal to be enabled.
            Theme configuration is loaded from omarchy/current/theme/ghostty.conf
            via Ghostty's config-file directive.
          '';
          default = true;
          example = true;
        };

        # Note: lazygit deferred to future work - see research.md
        # lazygit = lib.mkEnableOption "Lazygit theming" // {
        #   description = ''
        #     Configure Lazygit to use Omarchy theme (FUTURE).
        #
        #     This feature is not yet implemented. Lazygit requires color
        #     extraction from Omarchy themes and config generation.
        #   '';
        #   default = false;
        # };
      };
    };

    # ------------------------------------------------------------
    # Desktop Environment Theming (Stub)
    # ------------------------------------------------------------

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
        example = false;
      };
    };
  };

  # ==================================================================
  # IMPLEMENTATION (not part of public contract)
  # ==================================================================

  config = lib.mkIf config.programs.omarchy-theming.enable {
    # Implementation details not documented here
    # See home-manager/modules/omarchy-theming/ for actual code
  };
}

# ==================================================================
# USAGE EXAMPLES
# ==================================================================

# Example 1: Minimal enablement with defaults
# {
#   programs.omarchy-theming.enable = true;
# }

# Example 2: Terminal-only theming (no desktop)
# {
#   programs.omarchy-theming = {
#     enable = true;
#     terminal.enable = true;
#     desktop.enable = false;
#   };
# }

# Example 3: Only Ghostty theming, not Helix
# {
#   programs.omarchy-theming = {
#     enable = true;
#     terminal = {
#       enable = true;
#       applications = {
#         helix = false;
#         ghostty = true;
#       };
#     };
#   };
# }

# Example 4: Custom Omarchy package source
# {
#   programs.omarchy-theming = {
#     enable = true;
#     package = pkgs.fetchFromGitHub {
#       owner = "myuser";
#       repo = "omarchy-fork";
#       rev = "v1.2.3";
#       sha256 = "...";
#     };
#   };
# }

# ==================================================================
# ASSERTIONS AND WARNINGS (Implementation Detail)
# ==================================================================

# The module should include these assertions:
#
# 1. If terminal.enable = true and terminal-dev-environment is not enabled:
#    WARNING: Terminal theming requires programs.terminal-dev-environment.enable = true
#
# 2. If terminal.applications.helix = true and terminal-dev-environment.tools.editor = false:
#    WARNING: Helix theming requires programs.terminal-dev-environment.tools.editor = true
#
# 3. If terminal.applications.ghostty = true and terminal-dev-environment.tools.terminal = false:
#    WARNING: Ghostty theming requires programs.terminal-dev-environment.tools.terminal = true
#
# 4. If desktop.enable = true:
#    INFO: Desktop theming is experimental and not fully implemented yet

# ==================================================================
# ENVIRONMENT VARIABLES EXPOSED
# ==================================================================

# When desktop.enable = true:
#   OMARCHY_THEME_PATH = "${config.xdg.configHome}/omarchy/current/theme"
#     - Absolute path to active theme directory
#     - Can be used by scripts or manual desktop integration

# When terminal.enable = true:
#   PATH includes: "${config.home.homeDirectory}/.local/share/omarchy/bin"
#     - Provides access to omarchy-theme-next, omarchy-theme-set, etc.

# ==================================================================
# FILES MANAGED BY MODULE
# ==================================================================

# The module manages these filesystem locations:
#
# DECLARATIVE (managed by Nix):
#   ~/.config/omarchy/themes/default/          - Default theme files
#   ~/.local/share/omarchy/bin/*               - Omarchy binaries
#   ~/.local/share/omarchy/logo.txt            - Omarchy logo
#
# SEMI-DECLARATIVE (created once, then preserved):
#   ~/.config/omarchy/current/theme            - Active theme symlink
#
# USER-MANAGED (never touched by Nix):
#   ~/.config/omarchy/themes/<custom>/         - User-installed themes
#
# The module never modifies user's active theme selection after initial setup.

# ==================================================================
# VERSION COMPATIBILITY
# ==================================================================

# This module requires:
#   - NixOS 25.05 or later
#   - home-manager (compatible with NixOS 25.05)
#   - Omarchy source repository (any version with standard structure)
#
# Optional dependencies:
#   - programs.terminal-dev-environment (for terminal application integration)
#   - Keystone client module (for future Hyprland integration)

# ==================================================================
# MIGRATION AND DEPRECATION
# ==================================================================

# N/A - This is a new module with no previous versions.
#
# Future breaking changes will be documented here with migration guides.
