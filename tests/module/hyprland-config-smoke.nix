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

    assert_contains "${hyprpaperConf}" "preload=/home/testuser/.config/keystone/current/background" \
      "hyprpaper preloads the theme background before assigning wallpaper"
    assert_contains "${hyprpaperConf}" "wallpaper=,/home/testuser/.config/keystone/current/background" \
      "hyprpaper assigns the theme background to all monitors"

    assert_contains "${hypridleConf}" "lock_cmd=pidof hyprlock || hyprlock --immediate-render" \
      "hypridle uses immediate-render for the lock command"
    assert_contains "${hypridleConf}" "before_sleep_cmd=pidof hyprlock || hyprlock --immediate-render" \
      "hypridle uses immediate-render before suspend"
    assert_contains "${hypridleConf}" "on-timeout=pidof hyprlock || hyprlock --immediate-render" \
      "hypridle timeout locking uses immediate-render"

    assert_contains "${hyprlandConf}" "switch:on:Lid Switch, exec, pidof hyprlock || hyprlock --immediate-render; systemctl suspend" \
      "lid-close binding uses immediate-render before suspend"
    assert_contains "${startupLockScript}" "hyprlock_cmd=(hyprlock --immediate-render)" \
      "startup lock wrapper launches hyprlock with immediate-render"

    assert_not_contains "${hyprlockConf}" "disable_loading_bar" \
      "hyprlock config omits removed general.disable_loading_bar"
    assert_not_contains "${hyprlockConf}" "no_fade_in" \
      "hyprlock config omits removed general.no_fade_in"
    assert_not_contains "${hyprlockConf}" "placeholder_color" \
      "hyprlock config omits removed input-field.placeholder_color"
    if printf '%s\n' "$input_field_block" | grep -F "font_size" >/dev/null; then
      echo "FAIL: hyprlock input-field omits removed font_size" >&2
      exit 1
    else
      echo "PASS: hyprlock input-field omits removed font_size"
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
