{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.client.desktop.packages;
in
{
  options.keystone.client.desktop.packages = {
    enable = mkEnableOption "Essential desktop packages";
  };

  config = mkIf cfg.enable {
    # Font configuration
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        # Basic fonts
        noto-fonts
        noto-fonts-emoji

        # Nerd fonts for terminal icons
        nerd-fonts.caskaydia-mono
      ];
    };

    # Essential desktop packages
    environment.systemPackages = with pkgs; [
      # Hyprland utilities
      hyprshot # Screenshot tool
      hyprpicker # Color picker
      hyprsunset # Blue light filter
      brightnessctl # Brightness control

      # Clipboard and notifications
      wl-clipboard # Wayland clipboard
      libnotify # Notification library

      # File management
      nautilus # GNOME file manager

      # Basic desktop utilities
      glib # GLib library
      gnome-themes-extra # GTK themes

      # Terminal and shell utilities
      vim
      git
      curl
      wget
      unzip
      tree

      # System monitoring
      htop
    ];

    # Enable thumbnails in nautilus
    services.gnome.sushi.enable = true;
  };
}
