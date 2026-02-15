# Bluetooth Proximity Lock

The Bluetooth Proximity Lock feature automatically locks your screen when a trusted Bluetooth device (such as your phone) goes out of range. This provides an additional layer of security by ensuring your workstation locks when you walk away with your phone.

## Features

- **Automatic Locking**: Screen locks when your phone disconnects from Bluetooth
- **Debouncing**: Configurable delay to prevent false positives from brief connection drops
- **Systemd Integration**: Runs as a user service that starts with your desktop session
- **Logging**: Activity is logged to `/tmp/keystone-bluetooth-proximity-monitor.log` for debugging

## Configuration

### Finding Your Device Address

First, find your phone's Bluetooth MAC address:

```bash
# Pair your phone with your computer via Bluetooth settings
# Then list paired devices:
bluetoothctl devices
```

This will output something like:
```
Device AA:BB:CC:DD:EE:FF My Phone
Device 11:22:33:44:55:66 My Headphones
```

### Enabling the Feature

Add the following to your home-manager configuration:

```nix
keystone.desktop.hyprland.bluetoothProximityLock = {
  enable = true;
  deviceAddress = "AA:BB:CC:DD:EE:FF";  # Replace with your phone's MAC address
  disconnectDelay = 30;  # Lock after 30 seconds of disconnection (optional, default: 30)
};
```

### Configuration Options

- **`enable`** (boolean): Enable or disable the feature
- **`deviceAddress`** (string): Bluetooth MAC address of the device to monitor (format: `AA:BB:CC:DD:EE:FF`)
- **`disconnectDelay`** (integer, default: 30): Number of seconds to wait after device disconnection before locking the screen

## How It Works

1. The monitor service starts when you log into your Hyprland session
2. It checks every 5 seconds if your phone is connected
3. When the phone disconnects, it starts a countdown timer
4. If the phone remains disconnected for the configured delay (default 30 seconds), the screen locks
5. If the phone reconnects before the delay expires, the timer resets

## Troubleshooting

### Check Service Status

```bash
# Check if the service is running
systemctl --user status keystone-bluetooth-proximity-monitor

# View service logs
journalctl --user -u keystone-bluetooth-proximity-monitor -f
```

### Check Monitor Logs

```bash
# View the monitor's activity log
tail -f /tmp/keystone-bluetooth-proximity-monitor.log
```

### Test Device Connection

```bash
# Check if your device is connected
bluetoothctl info AA:BB:CC:DD:EE:FF | grep Connected
```

### Common Issues

**Service doesn't start:**
- Ensure Bluetooth is enabled on your system
- Verify the device address is correct
- Check that `keystone.desktop.bluetooth.enable = true` in your NixOS configuration

**Screen doesn't lock:**
- Verify the device is actually disconnecting (check logs)
- Ensure hyprlock is installed and working (`hyprlock` command)
- Check that the disconnect delay has been reached

**Too many false locks:**
- Increase the `disconnectDelay` to allow for brief connection drops
- Check signal strength - weak signals may cause frequent disconnections

## Integration with Other Lock Features

This feature works alongside the existing timeout-based locking from `hypridle`:

- **hypridle**: Locks screen after 5 minutes of inactivity (keyboard/mouse idle)
- **Bluetooth Proximity Lock**: Locks screen when you walk away with your phone
- **Lid Switch**: Locks screen when you close your laptop lid (if configured)

All methods use the same `hyprlock` screen locker, so they work seamlessly together.

## Security Considerations

- The Bluetooth connection is not encrypted or authenticated for proximity purposes - the monitor only checks if the device is connected
- This provides convenience security (locks when you leave) but doesn't prevent unauthorized access if someone steals your device while unlocked
- Always use strong password/PIN protection and enable full disk encryption
- Consider this an additional layer, not a replacement for other security measures

## Example Configurations

### Minimal Configuration
```nix
keystone.desktop.hyprland.bluetoothProximityLock = {
  enable = true;
  deviceAddress = "AA:BB:CC:DD:EE:FF";
};
```

### Quick Lock (15 seconds)
```nix
keystone.desktop.hyprland.bluetoothProximityLock = {
  enable = true;
  deviceAddress = "AA:BB:CC:DD:EE:FF";
  disconnectDelay = 15;  # Lock quickly after disconnection
};
```

### Patient Lock (60 seconds)
```nix
keystone.desktop.hyprland.bluetoothProximityLock = {
  enable = true;
  deviceAddress = "AA:BB:CC:DD:EE:FF";
  disconnectDelay = 60;  # Allow more time for connection drops
};
```
