{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.hyprland.bluetoothProximityLock;

  # Bluetooth proximity monitor script
  bluetoothProximityMonitor = pkgs.writeShellScriptBin "keystone-bluetooth-proximity-monitor" ''
    set -euo pipefail

    DEVICE_ADDRESS="${cfg.deviceAddress}"
    DISCONNECT_DELAY=${toString cfg.disconnectDelay}
    CHECK_INTERVAL=5

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    }

    log "Starting Bluetooth proximity monitor for device: $DEVICE_ADDRESS"
    log "Disconnect delay: ''${DISCONNECT_DELAY}s, Check interval: ''${CHECK_INTERVAL}s"

    # Wait for Bluetooth to be available
    while ! ${pkgs.bluez}/bin/bluetoothctl show &>/dev/null; do
      log "Waiting for Bluetooth adapter..."
      sleep 5
    done

    # Track disconnection time
    disconnected_since=""
    last_state="unknown"

    while true; do
      # Check if device is connected (using single pipeline for efficiency)
      # Note: Relies on bluetoothctl's "Connected: yes" output format
      # If format changes in future bluez versions, this may need adjustment
      if ${pkgs.bluez}/bin/bluetoothctl info "$DEVICE_ADDRESS" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Connected: yes"; then
        if [ "$last_state" != "connected" ]; then
          log "Device connected"
          last_state="connected"
        fi
        disconnected_since=""
      else
        if [ "$last_state" != "disconnected" ]; then
          log "Device disconnected"
          last_state="disconnected"
          disconnected_since=$(date +%s)
        fi

        # Check if disconnect delay has passed
        if [ -n "$disconnected_since" ]; then
          current_time=$(date +%s)
          disconnect_duration=$((current_time - disconnected_since))

          if [ $disconnect_duration -ge $DISCONNECT_DELAY ]; then
            log "Device disconnected for ''${disconnect_duration}s (threshold: ''${DISCONNECT_DELAY}s) - locking screen"
            
            # Use systemd-run with unit name to prevent duplicate instances
            # The --unit parameter ensures only one lock instance per trigger
            # Capture stderr to aid debugging if lock fails
            if error_msg=$(${pkgs.systemd}/bin/systemd-run --user --scope \
                --unit=hyprlock-bluetooth-lock \
                --property=Restart=no \
                ${pkgs.hyprlock}/bin/hyprlock 2>&1); then
              log "Screen lock triggered"
            else
              log "Screen lock failed: $error_msg"
            fi

            # Reset to avoid repeated locks
            disconnected_since=""
          fi
        fi
      fi

      sleep $CHECK_INTERVAL
    done
  '';
in
{
  options.keystone.desktop.hyprland.bluetoothProximityLock = {
    enable = mkEnableOption "Bluetooth proximity-based screen locking";

    deviceAddress = mkOption {
      type = types.str;
      example = "AA:BB:CC:DD:EE:FF";
      description = ''
        Bluetooth MAC address of the device to monitor (e.g., your phone).
        When this device disconnects, the screen will lock after the configured delay.
        Find your device address with: bluetoothctl devices
      '';
    };

    disconnectDelay = mkOption {
      type = types.int;
      default = 30;
      description = ''
        Number of seconds to wait after device disconnection before locking the screen.
        This debouncing prevents false positives from brief connection drops.
      '';
    };
  };

  config = mkIf (cfg.enable && config.keystone.desktop.hyprland.enable) {
    # Validate MAC address format
    assertions = [
      {
        assertion = builtins.match "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$" cfg.deviceAddress != null;
        message = "keystone.desktop.hyprland.bluetoothProximityLock.deviceAddress must be a valid MAC address (e.g., AA:BB:CC:DD:EE:FF)";
      }
    ];

    home.packages = [ bluetoothProximityMonitor ];

    # Systemd user service to run the Bluetooth monitor
    systemd.user.services.keystone-bluetooth-proximity-monitor = {
      Unit = {
        Description = "Keystone Bluetooth Proximity Monitor";
        Documentation = "https://github.com/ncrmro/keystone";
        After = [ "bluetooth.target" "graphical-session.target" ];
        Requires = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${bluetoothProximityMonitor}/bin/keystone-bluetooth-proximity-monitor";
        Restart = "on-failure";
        RestartSec = "10s";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
