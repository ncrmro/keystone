{
  wayland.windowManager.hyprland.settings = {
    env = [
      # Toolkit backends
      "GDK_BACKEND,wayland,x11"
      "QT_QPA_PLATFORM,wayland;xcb"
      "SDL_VIDEODRIVER,wayland"
      "CLUTTER_BACKEND,wayland"
      
      # XDG specifications
      "XDG_CURRENT_DESKTOP,Hyprland"
      "XDG_SESSION_TYPE,wayland"
      "XDG_SESSION_DESKTOP,Hyprland"
      
      # QT theming
      "QT_AUTO_SCREEN_SCALE_FACTOR,1"
      "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      "QT_QPA_PLATFORMTHEME,gtk3"
      
      # Firefox
      "MOZ_ENABLE_WAYLAND,1"
      "MOZ_DBUS_REMOTE,1"
      
      # NVIDIA specific (if needed)
      "LIBVA_DRIVER_NAME,nvidia"
      "XDG_SESSION_TYPE,wayland"
      "GBM_BACKEND,nvidia-drm"
      "__GLX_VENDOR_LIBRARY_NAME,nvidia"
      "WLR_NO_HARDWARE_CURSORS,1"
      
      # Cursor theme
      "XCURSOR_SIZE,24"
      "XCURSOR_THEME,Adwaita"
    ];
  };
}