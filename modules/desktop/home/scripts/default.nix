{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

  # Screen recording script using gpu-screen-recorder
  #
  # Waybar Integration:
  # The waybar module "custom/screenrecording-indicator" uses signal-based updates
  # instead of polling for efficiency. When recording starts or stops, we send
  # RTMIN+8 signal to waybar (pkill -RTMIN+8 waybar) which triggers it to re-run
  # the indicator's exec command and update the display immediately.
  #
  # The waybar config uses "signal": 8 which maps to RTMIN+8.
  # See: modules/keystone/desktop/home/components/waybar.nix
  #
  keystoneScreenrecord = pkgs.writeShellScriptBin "keystone-screenrecord" ''
    [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
    OUTPUT_DIR="''${KEYSTONE_SCREENRECORD_DIR:-''${XDG_VIDEOS_DIR:-$HOME/Videos}}"

    if [[ ! -d "$OUTPUT_DIR" ]]; then
      ${pkgs.libnotify}/bin/notify-send "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
      exit 1
    fi

    DESKTOP_AUDIO="false"
    MICROPHONE_AUDIO="false"
    STOP_RECORDING="false"

    for arg in "$@"; do
      case "$arg" in
        --with-desktop-audio) DESKTOP_AUDIO="true" ;;
        --with-microphone-audio) MICROPHONE_AUDIO="true" ;;
        --stop) STOP_RECORDING="true" ;;
      esac
    done

    start_screenrecording() {
      local filename="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
      local audio_args=""

      if [[ "$DESKTOP_AUDIO" == "true" && "$MICROPHONE_AUDIO" == "true" ]]; then
        audio_args="-a default_output|default_input"
      elif [[ "$DESKTOP_AUDIO" == "true" ]]; then
        audio_args="-a default_output"
      elif [[ "$MICROPHONE_AUDIO" == "true" ]]; then
        audio_args="-a default_input"
      fi

      ${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder -w portal -f 60 -encoder gpu -o "$filename" $audio_args -ac aac &
      ${pkgs.libnotify}/bin/notify-send "Screen recording started" -t 2000
      ${pkgs.procps}/bin/pkill -RTMIN+8 waybar
    }

    stop_screenrecording() {
      ${pkgs.procps}/bin/pkill -SIGINT -f "^gpu-screen-recorder"

      # Wait up to 5 seconds for clean shutdown
      local count=0
      while ${pkgs.procps}/bin/pgrep -f "^gpu-screen-recorder" >/dev/null && [ $count -lt 50 ]; do
        sleep 0.1
        count=$((count + 1))
      done

      if ${pkgs.procps}/bin/pgrep -f "^gpu-screen-recorder" >/dev/null; then
        ${pkgs.procps}/bin/pkill -9 -f "^gpu-screen-recorder"
        ${pkgs.libnotify}/bin/notify-send "Screen recording error" "Recording had to be force-killed. Video may be corrupted." -u critical -t 5000
      else
        ${pkgs.libnotify}/bin/notify-send "Screen recording saved to $OUTPUT_DIR" -t 2000
      fi
      ${pkgs.procps}/bin/pkill -RTMIN+8 waybar
    }

    screenrecording_active() {
      ${pkgs.procps}/bin/pgrep -f "^gpu-screen-recorder" >/dev/null
    }

    if screenrecording_active; then
      stop_screenrecording
    elif [[ "$STOP_RECORDING" == "false" ]]; then
      start_screenrecording
    else
      exit 1
    fi
  '';

  # Audio switch script
  keystoneAudioSwitch = pkgs.writeShellScriptBin "keystone-audio-switch" ''
    focused_monitor="$(${hyprlandPkg}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true).name')"

    sinks=$(${pkgs.pulseaudio}/bin/pactl -f json list sinks | ${pkgs.jq}/bin/jq '[.[] | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))]')
    sinks_count=$(echo "$sinks" | ${pkgs.jq}/bin/jq '. | length')

    if [ "$sinks_count" -eq 0 ]; then
      ${pkgs.swayosd}/bin/swayosd-client \
        --monitor "$focused_monitor" \
        --custom-message "No audio devices found"
      exit 1
    fi

    current_sink_name=$(${pkgs.pulseaudio}/bin/pactl get-default-sink)
    current_sink_index=$(echo "$sinks" | ${pkgs.jq}/bin/jq -r --arg name "$current_sink_name" 'map(.name) | index($name)')

    if [ "$current_sink_index" != "null" ]; then
      next_sink_index=$(((current_sink_index + 1) % sinks_count))
    else
      next_sink_index=0
    fi

    next_sink=$(echo "$sinks" | ${pkgs.jq}/bin/jq -r ".[$next_sink_index]")
    next_sink_name=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.name')

    next_sink_description=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.description')
    if [ "$next_sink_description" = "(null)" ] || [ "$next_sink_description" = "null" ] || [ -z "$next_sink_description" ]; then
      sink_id=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.properties."object.id"')
      next_sink_description=$(${pkgs.wireplumber}/bin/wpctl status | grep -E "\s+\*?\s+''${sink_id}\." | sed -E 's/^.*[0-9]+\.\s+//' | sed -E 's/\s+\[.*$//')
    fi

    next_sink_volume=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r \
      '.volume | to_entries[0].value.value_percent | sub("%"; "")')
    next_sink_is_muted=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.mute')

    if [ "$next_sink_is_muted" = "true" ] || [ "$next_sink_volume" -eq 0 ]; then
      icon_state="muted"
    elif [ "$next_sink_volume" -le 33 ]; then
      icon_state="low"
    elif [ "$next_sink_volume" -le 66 ]; then
      icon_state="medium"
    else
      icon_state="high"
    fi

    next_sink_volume_icon="sink-volume-''${icon_state}-symbolic"

    if [ "$next_sink_name" != "$current_sink_name" ]; then
      ${pkgs.pulseaudio}/bin/pactl set-default-sink "$next_sink_name"
    fi

    ${pkgs.swayosd}/bin/swayosd-client \
      --monitor "$focused_monitor" \
      --custom-message "$next_sink_description" \
      --custom-icon "$next_sink_volume_icon"
  '';

  # Idle toggle script
  keystoneIdleToggle = pkgs.writeShellScriptBin "keystone-idle-toggle" ''
    if ${pkgs.procps}/bin/pgrep -x hypridle > /dev/null; then
      ${pkgs.procps}/bin/pkill -x hypridle
      ${pkgs.libnotify}/bin/notify-send "󰅶  Idle inhibitor enabled" "Screen will not lock automatically"
    else
      setsid ${pkgs.uwsm}/bin/uwsm app -- ${pkgs.hypridle}/bin/hypridle &
      ${pkgs.libnotify}/bin/notify-send "󰾪  Idle inhibitor disabled" "Screen will lock after timeout"
    fi
  '';

  # Nightlight toggle script
  keystoneNightlightToggle = pkgs.writeShellScriptBin "keystone-nightlight-toggle" ''
    ON_TEMP=4000
    OFF_TEMP=6000

    if ! ${pkgs.procps}/bin/pgrep -x hyprsunset; then
      setsid ${pkgs.uwsm}/bin/uwsm app -- ${pkgs.hyprsunset}/bin/hyprsunset &
      sleep 1
    fi

    CURRENT_TEMP=$(${hyprlandPkg}/bin/hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+')

    if [[ "$CURRENT_TEMP" == "$OFF_TEMP" ]]; then
      ${hyprlandPkg}/bin/hyprctl hyprsunset temperature $ON_TEMP
      ${pkgs.libnotify}/bin/notify-send "  Nightlight screen temperature"
    else
      ${hyprlandPkg}/bin/hyprctl hyprsunset temperature $OFF_TEMP
      ${pkgs.libnotify}/bin/notify-send "   Daylight screen temperature"
    fi
  '';

  # Walker launcher wrapper for menus
  keystoneLaunchWalker = pkgs.writeShellScriptBin "keystone-launch-walker" (
    builtins.readFile ./keystone-launch-walker.sh
  );

  # Main menu script
  keystoneMenu = pkgs.writeShellScriptBin "keystone-menu" (builtins.readFile ./keystone-menu.sh);

  # Keybindings viewer script
  keystoneMenuKeybindings = pkgs.writeShellScriptBin "keystone-menu-keybindings" (
    builtins.readFile ./keystone-menu-keybindings.sh
  );

  # Battery monitor script
  keystoneBatteryMonitor = pkgs.writeShellScriptBin "keystone-battery-monitor" ''
    BATTERY_THRESHOLD=10
    NOTIFICATION_FLAG="/run/user/$UID/keystone_battery_notified"

    # Get battery level
    BATTERY_LEVEL=$(${pkgs.upower}/bin/upower -i $(${pkgs.upower}/bin/upower -e | grep 'BAT') | grep -E "percentage" | awk '{print $2}' | tr -d '%')
    BATTERY_STATE=$(${pkgs.upower}/bin/upower -i $(${pkgs.upower}/bin/upower -e | grep 'BAT') | grep -E "state" | awk '{print $2}')

    send_notification() {
      ${pkgs.libnotify}/bin/notify-send -u critical " Time to recharge!" "Battery is down to ''${1}%" -i battery-caution -t 30000
    }

    if [[ -n "$BATTERY_LEVEL" && "$BATTERY_LEVEL" =~ ^[0-9]+$ ]]; then
      if [[ $BATTERY_STATE == "discharging" && $BATTERY_LEVEL -le $BATTERY_THRESHOLD ]]; then
        if [[ ! -f $NOTIFICATION_FLAG ]]; then
          send_notification $BATTERY_LEVEL
          touch $NOTIFICATION_FLAG
        fi
      else
        rm -f $NOTIFICATION_FLAG
      fi
    fi
  '';
in
{
  config = mkIf cfg.enable {
    home.packages = [
      keystoneScreenrecord
      keystoneAudioSwitch
      keystoneIdleToggle
      keystoneNightlightToggle
      keystoneBatteryMonitor
      keystoneLaunchWalker
      keystoneMenu
      keystoneMenuKeybindings
      # Dependencies that should be available
      pkgs.gpu-screen-recorder
      pkgs.libxkbcommon # for xkbcli in keybindings menu
      pkgs.hypridle
    ];
  };
}
