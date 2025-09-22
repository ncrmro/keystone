lib: {
  keystoneOptions = {
    full_name = lib.mkOption {
      type = lib.types.str;
      description = "Main user's full name";
    };
    
    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable desktop environment with Hyprland";
      };
      
      monitors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ",preferred,auto,auto" ];
        description = "Monitor configuration for Hyprland";
        example = [ "DP-1,1920x1080@60,0x0,1" "HDMI-A-1,1920x1080@60,1920x0,1" ];
      };
      
      wallpaper = lib.mkOption {
        type = lib.types.str;
        default = "~/Pictures/wallpaper.jpg";
        description = "Path to wallpaper image";
      };
    };
  };
}
