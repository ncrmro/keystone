{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  
  # Yazi wrapper script for file picker integration
  # This script is pre-configured and ready to use once xdg-desktop-portal-termfilechooser is installed
  yaziFilePickerWrapper = pkgs.writeShellScript "yazi-file-picker" ''
    #!/usr/bin/env bash
    # Yazi wrapper for XDG Desktop Portal file picker
    # Args: $1 = output file path, $2 = save mode (true/false)
    
    out="$1"
    saved="$2"
    
    # Launch yazi in ghostty terminal with chooser mode
    ${pkgs.ghostty}/bin/ghostty \
      --class=yazi-filepicker \
      --title="File Picker" \
      -e ${pkgs.yazi}/bin/yazi --chooser-file="$out"
  '';
  
in
{
  config = mkIf cfg.enable {
    # Create XDG portal configuration directory structure
    # These files are created automatically but yazi file picker requires
    # xdg-desktop-portal-termfilechooser to be installed separately
    xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      # Use GTK portal for most functions
      default=gtk
      
      # To enable yazi as file picker:
      # 1. Install xdg-desktop-portal-termfilechooser (see docs/yazi-file-picker.md)
      # 2. Uncomment the following line:
      # org.freedesktop.impl.portal.FileChooser=termfilechooser
      # 3. Restart xdg-desktop-portal: systemctl --user restart xdg-desktop-portal.service
    '';
    
    # Create pre-configured termfilechooser config with yazi wrapper
    xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
      [filechooser]
      # Wrapper script for yazi file picker (pre-configured)
      # This config is ready to use once xdg-desktop-portal-termfilechooser is installed
      cmd=${yaziFilePickerWrapper}
    '';
    
    # Firefox configuration for XDG portal file picker
    # This enables Firefox to use the portal system for file selection
    programs.firefox = mkIf (config.programs.firefox.enable or false) {
      profiles = mkIf (config.programs.firefox.profiles != {}) (
        mapAttrs (name: profile: {
          settings = {
            # Enable XDG desktop portal for file picker
            "widget.use-xdg-desktop-portal.file-picker" = 1;
          };
        }) config.programs.firefox.profiles
      );
    };
  };
}

