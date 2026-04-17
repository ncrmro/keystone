{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
in
{
  config = mkIf desktopCfg.enable {
    programs.hyprlock = {
      enable = mkDefault true;
      settings = {
        auth = {
          fingerprint.enabled = true;
        };

        background = {
          monitor = "";
          # Use the theme background directly so the lockscreen renders on
          # first boot (before hyprpaper sets the wallpaper). The theme
          # symlink is created by home-manager activation, which runs
          # before greetd starts the session.
          path = "${config.xdg.configHome}/keystone/current/background";
          blur_passes = 3;
          brightness = 0.5;
        };

        input-field = {
          monitor = "";
          size = "600, 100";
          position = "0, 0";
          halign = "center";
          valign = "center";

          inner_color = "rgb(1e1e2e)";
          outer_color = "rgb(89b4fa)";
          outline_thickness = 4;

          font_family = "JetBrainsMono Nerd Font";
          font_color = "rgb(cdd6f4)";

          placeholder_text = "  Enter Password";
          check_color = "rgb(a6e3a1)";
          fail_text = "Wrong ($ATTEMPTS)";

          rounding = 0;
          shadow_passes = 0;
          fade_on_empty = false;
        };

        label = {
          monitor = "";
          text = "$FPRINTPROMPT";
          text_align = "center";
          color = "rgb(f9e2af)";
          font_size = 24;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, -100";
          halign = "center";
          valign = "center";
        };
      };
    };
  };
}
