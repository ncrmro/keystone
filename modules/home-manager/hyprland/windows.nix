{
  wayland.windowManager.hyprland.settings = {
    dwindle = {
      pseudotile = true;
      preserve_split = true;
      smart_split = false;
      smart_resizing = true;
    };
    
    master = {
      new_is_master = true;
      mfact = 0.55;
    };
    
    windowrulev2 = [
      # Make floating windows center
      "center,floating:1"
      
      # Opacity rules
      "opacity 0.95 0.95,class:^(Alacritty)$"
      "opacity 0.95 0.95,class:^(kitty)$"
      "opacity 0.90 0.90,class:^(thunar)$"
      
      # Workspace assignments
      "workspace 2,class:^(firefox)$"
      "workspace 3,class:^(thunderbird)$"
      "workspace 4,class:^(discord)$"
      "workspace 4,class:^(webcord)$"
      "workspace 5,class:^(Spotify)$"
      "workspace 5,class:^(spotify)$"
      
      # Floating windows
      "float,class:^(pavucontrol)$"
      "float,class:^(nm-connection-editor)$"
      "float,class:^(blueman-manager)$"
      "float,class:^(org.gnome.Calculator)$"
      "float,class:^(gnome-calculator)$"
      "float,title:^(Picture-in-Picture)$"
      
      # Size rules for floating windows
      "size 800 600,class:^(pavucontrol)$"
      "size 800 600,class:^(nm-connection-editor)$"
      "size 600 500,class:^(blueman-manager)$"
      "size 400 500,class:^(org.gnome.Calculator)$"
      
      # No shadow for tiled windows
      "noshadow,floating:0"
    ];
    
    layerrule = [
      "blur,waybar"
      "ignorezero,waybar"
      "blur,notifications"
      "ignorezero,notifications"
    ];
  };
}