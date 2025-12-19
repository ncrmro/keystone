{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.hyprland;
  terminalCfg = config.keystone.terminal;
  hasNvidiaDrivers =
    if osConfig ? services.xserver.videoDrivers then
      builtins.elem "nvidia" osConfig.services.xserver.videoDrivers
    else
      false;
  nvidiaEnv = [
    "NVD_BACKEND,direct"
    "LIBVA_DRIVER_NAME,nvidia"
    "__GLX_VENDOR_LIBRARY_NAME,nvidia"
  ];
in
{
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.settings = {
      env = mkDefault (
        (optionals hasNvidiaDrivers nvidiaEnv)
        ++ [
          # Display scaling
          "GDK_SCALE,${toString cfg.scale}"

          # Cursor size
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"

          # Cursor theme
          "XCURSOR_THEME,Adwaita"
          "HYPRCURSOR_THEME,Adwaita"

          # Force all apps to use Wayland
          "GDK_BACKEND,wayland"
          "QT_QPA_PLATFORM,wayland"
          "QT_STYLE_OVERRIDE,kvantum"
          "SDL_VIDEODRIVER,wayland"
          "MOZ_ENABLE_WAYLAND,1"
          "ELECTRON_OZONE_PLATFORM_HINT,wayland"
          "OZONE_PLATFORM,wayland"

          # Make Chromium use XCompose and all Wayland
          "CHROMIUM_FLAGS,\"--enable-features=UseOzonePlatform --ozone-platform=wayland --gtk-version=4\""

          # Make .desktop files available for wofi
          "XDG_DATA_DIRS,$XDG_DATA_DIRS:$HOME/.nix-profile/share:/nix/var/nix/profiles/default/share"

          # Use XCompose file
          "XCOMPOSEFILE,~/.XCompose"
          "EDITOR,${terminalCfg.editor}"

          # GTK theme
          "GTK_THEME,Adwaita:dark"
        ]
      );

      xwayland = mkDefault {
        force_zero_scaling = true;
      };

      ecosystem = mkDefault {
        no_update_news = true;
      };
    };
  };
}
