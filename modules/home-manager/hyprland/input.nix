{
  wayland.windowManager.hyprland.settings = {
    input = {
      kb_layout = "us";
      kb_variant = "";
      kb_model = "";
      kb_options = "";
      kb_rules = "";
      
      follow_mouse = 1;
      
      touchpad = {
        natural_scroll = true;
        disable_while_typing = true;
        tap-to-click = true;
        drag_lock = false;
      };
      
      sensitivity = 0; # -1.0 - 1.0, 0 means no modification
    };
    
    gestures = {
      workspace_swipe = true;
      workspace_swipe_fingers = 3;
      workspace_swipe_distance = 300;
      workspace_swipe_invert = true;
      workspace_swipe_min_speed_to_force = 30;
      workspace_swipe_cancel_ratio = 0.5;
      workspace_swipe_create_new = true;
      workspace_swipe_forever = true;
    };
  };
}