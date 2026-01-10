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
    xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      # Use GTK portal for most functions
      default=gtk
      
      # To enable yazi as file picker, install xdg-desktop-portal-termfilechooser
      # and uncomment the following line:
      # org.freedesktop.impl.portal.FileChooser=termfilechooser
    '';
    
    # Create placeholder config for termfilechooser
    xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
      [filechooser]
      # Wrapper script for yazi file picker
      # To enable, install xdg-desktop-portal-termfilechooser package
      cmd=${yaziFilePickerWrapper}
    '';
    
    # Firefox configuration for XDG portal file picker
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

