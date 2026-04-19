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
    # Isolate hyprlock inside a dedicated user service so that a config-parse
    # SIGABRT does not propagate into Hyprland's crash reporter and take down
    # the entire session.  Type=oneshot / Restart=no means one invocation per
    # start request; the Slice keeps it inside lock.slice for resource
    # accounting.  Lock-triggering callers (hypridle, keystone-startup-lock)
    # use "systemctl --user start --no-block hyprlock" so they remain
    # unblocked while the service runs.
    systemd.user.services.hyprlock = {
      Unit = {
        Description = "Hyprlock screen locker";
        Documentation = "https://wiki.hyprland.org/Hypr-Ecosystem/hyprlock/";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.hyprlock}/bin/hyprlock";
        Restart = "no";
        Slice = "lock.slice";
      };
    };

    programs.hyprlock = {
      enable = mkDefault true;
      settings = {
        source = mkDefault "${config.xdg.configHome}/keystone/current/theme/hyprlock.conf";

        general = {
          disable_loading_bar = true;
          no_fade_in = false;
        };

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

          inner_color = "$inner_color";
          outer_color = "$outer_color";
          outline_thickness = 4;

          font_family = "JetBrainsMono Nerd Font";
          font_size = 32;
          font_color = "$font_color";

          placeholder_color = "$placeholder_color";
          placeholder_text = "  Enter Password";
          check_color = "$check_color";
          fail_text = "Wrong ($ATTEMPTS)";

          rounding = 0;
          shadow_passes = 0;
          fade_on_empty = false;
        };

        label = {
          monitor = "";
          text = "$FPRINTPROMPT";
          text_align = "center";
          color = "$font_color";
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
