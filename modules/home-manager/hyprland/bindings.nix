{
  wayland.windowManager.hyprland.settings = {
    # Modifier key
    "$mod" = "SUPER";
    
    bind = [
      # Application launchers
      "$mod, Return, exec, $terminal"
      "$mod, Q, killactive"
      "$mod, M, exit"
      "$mod, E, exec, $fileManager"
      "$mod, V, togglefloating"
      "$mod, R, exec, $menu"
      "$mod, P, pseudo"
      "$mod, J, togglesplit"
      "$mod, F, fullscreen, 1"
      "$mod SHIFT, F, fullscreen, 0"
      
      # Move focus with vim keys
      "$mod, H, movefocus, l"
      "$mod, L, movefocus, r" 
      "$mod, K, movefocus, u"
      "$mod, J, movefocus, d"
      
      # Switch workspaces
      "$mod, 1, workspace, 1"
      "$mod, 2, workspace, 2"
      "$mod, 3, workspace, 3"
      "$mod, 4, workspace, 4"
      "$mod, 5, workspace, 5"
      "$mod, 6, workspace, 6"
      "$mod, 7, workspace, 7"
      "$mod, 8, workspace, 8"
      "$mod, 9, workspace, 9"
      "$mod, 0, workspace, 10"
      
      # Move active window to workspace
      "$mod SHIFT, 1, movetoworkspace, 1"
      "$mod SHIFT, 2, movetoworkspace, 2"
      "$mod SHIFT, 3, movetoworkspace, 3"
      "$mod SHIFT, 4, movetoworkspace, 4"
      "$mod SHIFT, 5, movetoworkspace, 5"
      "$mod SHIFT, 6, movetoworkspace, 6"
      "$mod SHIFT, 7, movetoworkspace, 7"
      "$mod SHIFT, 8, movetoworkspace, 8"
      "$mod SHIFT, 9, movetoworkspace, 9"
      "$mod SHIFT, 0, movetoworkspace, 10"
      
      # Audio control
      ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
      ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      
      # Brightness control
      ", XF86MonBrightnessUp, exec, brightnessctl set 10%+"
      ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"
      
      # Screenshot
      ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      "$mod, Print, exec, grim - | wl-copy"
    ];
    
    bindm = [
      # Mouse bindings
      "$mod, mouse:272, movewindow"
      "$mod, mouse:273, resizewindow"
    ];
  };
}