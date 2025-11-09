{ config, lib, pkgs, ... }:

let
  cfg = config.programs.omarchy-theming;
in
{
  config = lib.mkIf cfg.enable {
    # Activation script to set up initial theme symlink
    # This runs after all files are written but before final setup
    home.activation.omarchy-theme-setup = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Create directories if they don't exist
      $DRY_RUN_CMD mkdir -p ${config.xdg.configHome}/omarchy/current
      $DRY_RUN_CMD mkdir -p ${config.home.homeDirectory}/.local/share/omarchy

      # Create initial theme symlink if it doesn't exist (idempotent)
      # This preserves user's theme choice across rebuilds
      THEME_SYMLINK="${config.xdg.configHome}/omarchy/current/theme"
      DEFAULT_THEME="${config.xdg.configHome}/omarchy/themes/default"
      
      if [ ! -L "$THEME_SYMLINK" ]; then
        if [ -d "$DEFAULT_THEME" ]; then
          $VERBOSE_ECHO "Creating initial theme symlink to default theme"
          $DRY_RUN_CMD ln -sf "$DEFAULT_THEME" "$THEME_SYMLINK"
        else
          $VERBOSE_ECHO "Warning: Default theme directory not found at $DEFAULT_THEME"
        fi
      else
        # Symlink exists - check if it's broken and fix if needed
        if [ ! -e "$THEME_SYMLINK" ]; then
          $VERBOSE_ECHO "Theme symlink is broken, recreating to default theme"
          $DRY_RUN_CMD rm -f "$THEME_SYMLINK"
          if [ -d "$DEFAULT_THEME" ]; then
            $DRY_RUN_CMD ln -sf "$DEFAULT_THEME" "$THEME_SYMLINK"
          fi
        else
          $VERBOSE_ECHO "Theme symlink already exists and is valid, preserving user's theme choice"
        fi
      fi
    '';
  };
}
