{
  wayland.windowManager.hyprland.settings = {
    general = {
      gaps_in = 5;
      gaps_out = 10;
      border_size = 2;
      "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
      "col.inactive_border" = "rgba(595959aa)";
      
      layout = "dwindle";
      
      allow_tearing = false;
    };
    
    decoration = {
      rounding = 8;
      
      blur = {
        enabled = true;
        size = 8;
        passes = 3;
        new_optimizations = true;
        xray = true;
        ignore_opacity = false;
      };
      
      drop_shadow = true;
      shadow_range = 4;
      shadow_render_power = 3;
      "col.shadow" = "rgba(1a1a1aee)";
    };
    
    animations = {
      enabled = true;
      
      bezier = [
        "myBezier, 0.05, 0.9, 0.1, 1.05"
      ];
      
      animation = [
        "windows, 1, 7, myBezier"
        "windowsOut, 1, 7, default, popin 80%"
        "border, 1, 10, default"
        "borderangle, 1, 8, default"
        "fade, 1, 7, default"
        "workspaces, 1, 6, default"
      ];
    };
    
    misc = {
      force_default_wallpaper = 0;
      disable_hyprland_logo = true;
      disable_splash_rendering = true;
      vfr = true;
    };
  };
}