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
        general = {
          disable_loading_bar = true;
          no_fade_in = false;
        };

        auth = {
          fingerprint.enabled = true;
        };

        background = {
          monitor = "";
          # Locking is security-critical, so the lockscreen must not depend on
          # mutable theme symlinks existing at login time.
          path = "screenshot";
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
          font_size = 32;
          font_color = "rgb(cdd6f4)";

          placeholder_color = "rgb(9399b2)";
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
