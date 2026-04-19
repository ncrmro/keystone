{
  pkgs,
  lib,
  self,
  home-manager,
}:
let
  evalDesktop =
    extraModules:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.terminal
        self.homeModules.desktop
        {
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";

          programs.ssh.enableDefaultConfig = false;

          keystone.terminal = {
            enable = true;
            git = {
              userName = "Test User";
              userEmail = "test@test";
            };
          };

          keystone.desktop.enable = true;
          wayland.windowManager.hyprland.enable = true;
        }
      ]
      ++ extraModules;
    }).config;

  desktopConfig = evalDesktop [ ];
  hyprlandConf = desktopConfig.xdg.configFile."hypr/hyprland.conf".source;
  hypridleConf = desktopConfig.xdg.configFile."hypr/hypridle.conf".source;
  hyprlockConf = desktopConfig.xdg.configFile."hypr/hyprlock.conf".source;
  hyprpaperConf = desktopConfig.xdg.configFile."hypr/hyprpaper.conf".source;
  hyprlandPkg = desktopConfig.wayland.windowManager.hyprland.package;
  startupLockScript = ../../modules/desktop/home/scripts/keystone-startup-lock.sh;

  # Eval-time hardening checks: verify the hyprlock systemd service is defined
  # with the correct isolation attributes (Type=oneshot, Restart=no,
  # Slice=lock.slice).  These are evaluated during nix flake check so that a
  # future refactor that drops the service definition is caught pre-merge.
  boolString = v: if v then "true" else "false";
  hyprlockService = desktopConfig.systemd.user.services.hyprlock or { };
  svcExists = hyprlockService ? Service;
  svcType = (hyprlockService.Service or { }).Type or "";
  svcRestart = (hyprlockService.Service or { }).Restart or "";
  svcSlice = (hyprlockService.Service or { }).Slice or "";
in
pkgs.runCommand "hyprland-config-smoke"
  {
    nativeBuildInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    set -euo pipefail

    input_field_block="$(sed -n '/^input-field {/,/^}/p' "${hyprlockConf}")"

    assert_contains() {
      local file="$1"
      local needle="$2"
      local description="$3"

      if grep -F "$needle" "$file" >/dev/null; then
        echo "PASS: $description"
      else
        echo "FAIL: $description" >&2
        echo "missing: $needle" >&2
        exit 1
      fi
    }

    assert_not_contains() {
      local file="$1"
      local needle="$2"
      local description="$3"

      if grep -F "$needle" "$file" >/dev/null; then
        echo "FAIL: $description" >&2
        echo "unexpected: $needle" >&2
        exit 1
      else
        echo "PASS: $description"
      fi
    }

    check() {
      if [ "$1" = "true" ]; then
        echo "PASS: $2"
      else
        echo "FAIL: $2" >&2
        exit 1
      fi
    }

    assert_contains "${hyprpaperConf}" "preload=/home/testuser/.config/keystone/current/background" \
      "hyprpaper preloads the theme background before assigning wallpaper"
    assert_contains "${hyprpaperConf}" "wallpaper=,/home/testuser/.config/keystone/current/background" \
      "hyprpaper assigns the theme background to all monitors"

    # hypridle must invoke the systemd service rather than raw hyprlock so that
    # a config-parse SIGABRT is contained in lock.slice.
    assert_contains "${hypridleConf}" "lock_cmd=pidof hyprlock || systemctl --user start --no-block hyprlock" \
      "hypridle lock command invokes hyprlock via systemd service"
    assert_contains "${hypridleConf}" "before_sleep_cmd=pidof hyprlock || systemctl --user start --no-block hyprlock" \
      "hypridle locks before suspend via systemd service"
    assert_contains "${hypridleConf}" "on-timeout=pidof hyprlock || systemctl --user start --no-block hyprlock" \
      "hypridle timeout triggers lock via systemd service"
    assert_not_contains "${hypridleConf}" "immediate-render" \
      "hypridle does not use --immediate-render (causes blank lock screen)"

    assert_contains "${hyprlandConf}" "switch:on:Lid Switch, exec, pidof hyprlock || systemctl --user start --no-block hyprlock; systemctl suspend" \
      "lid-close binding locks via systemd service and suspends"

    # keystone-startup-lock must use systemd-run --scope so hyprlock is not a
    # direct child of the Hyprland exec-once process tree when it aborts.
    assert_contains "${startupLockScript}" "systemd-run --user --scope --slice=lock.slice" \
      "startup lock wrapper isolates hyprlock in a systemd scope"

    # Hardening: verify the systemd.user.services.hyprlock service is defined
    # with Type=oneshot, Restart=no, Slice=lock.slice so a config-parse
    # SIGABRT is contained and does not propagate into Hyprland's crash
    # reporter.
    check "${boolString svcExists}" \
      "systemd.user.services.hyprlock is defined"
    check "${boolString (svcType == "oneshot")}" \
      "hyprlock systemd service is Type=oneshot (got: ${svcType})"
    check "${boolString (svcRestart == "no")}" \
      "hyprlock systemd service has Restart=no (got: ${svcRestart})"
    check "${boolString (svcSlice == "lock.slice")}" \
      "hyprlock systemd service is in Slice=lock.slice (got: ${svcSlice})"

    assert_contains "${hyprlockConf}" "source=" \
      "hyprlock sources theme colors from theme hyprlock.conf"
    assert_contains "${hyprlockConf}" "disable_loading_bar" \
      "hyprlock general section is present"
    assert_contains "${hyprlockConf}" "inner_color=\$inner_color" \
      "hyprlock uses theme variable for inner_color"
    assert_contains "${hyprlockConf}" "font_color=\$font_color" \
      "hyprlock uses theme variable for font_color"
    assert_contains "${hyprlockConf}" "placeholder_color=\$placeholder_color" \
      "hyprlock uses theme variable for placeholder_color"
    if printf '%s\n' "$input_field_block" | grep -F "font_size" >/dev/null; then
      echo "PASS: hyprlock input-field includes font_size"
    else
      echo "FAIL: hyprlock input-field missing font_size" >&2
      exit 1
    fi

    export HOME="$PWD/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    mkdir -p "$XDG_CONFIG_HOME/keystone/current/theme" "$XDG_RUNTIME_DIR"
    : > "$XDG_CONFIG_HOME/keystone/current/theme/hyprland.conf"

    "${hyprlandPkg}/bin/Hyprland" --verify-config -c "${hyprlandConf}" >"$PWD/hyprland-verify.log" 2>&1
    assert_contains "$PWD/hyprland-verify.log" "config ok" \
      "Hyprland verifies the rendered desktop config successfully"

    touch "$out"
  ''
