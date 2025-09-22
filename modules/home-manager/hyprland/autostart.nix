{
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "waybar"
      "mako"
      "hyprpaper"
      "hypridle"
      
      # Audio
      "pavucontrol --tab=3"
      
      # Authentication agent
      "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      
      # Clipboard manager
      "wl-paste --type text --watch cliphist store"
      "wl-paste --type image --watch cliphist store"
    ];
  };
}