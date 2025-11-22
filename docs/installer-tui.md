# Keystone Installer - Interactive TUI

The Keystone installer ISO now includes an interactive Terminal User Interface (TUI) that automatically helps you configure network connectivity for remote installation.

## Overview

When you boot from the Keystone ISO, the installer automatically:

1. **Checks for Ethernet connectivity** - If an Ethernet cable is connected and has obtained an IP address, it displays the IP and installation instructions
2. **Offers WiFi setup** - If no Ethernet connection is detected, it prompts you to configure WiFi
3. **Guides the installation** - Once network is configured, it shows the exact `nixos-anywhere` command to run from your deployment machine

## Features

### Automatic Network Detection

The installer checks all network interfaces for IP addresses on boot. If it finds an Ethernet connection (interfaces starting with `eth` or `en`), it displays:

```
✓ Network Connected
Interface: eth0 - IP: 192.168.1.100

Ready for Installation
From your deployment machine, run:
nixos-anywhere --flake .#your-config root@192.168.1.100
```

### Interactive WiFi Setup

If no Ethernet connection is detected, the installer offers to scan for WiFi networks:

1. **Scan**: Scans for available WiFi networks using NetworkManager
2. **Select**: Shows a list of available networks to choose from
3. **Authenticate**: Prompts for the WiFi password (masked input)
4. **Connect**: Attempts to connect and displays the IP address once connected

### User-Friendly Interface

Built with [Ink](https://github.com/vadimdemedes/ink) (React for terminal UIs), the installer provides:

- Clean, modern terminal interface
- Loading spinners during network operations
- Clear error messages and retry options
- Keyboard navigation for network selection

## Usage

### Typical Workflow

1. **Boot from USB/ISO**: Boot your target machine from the Keystone installer
2. **Wait for network check**: The installer automatically checks for connectivity (~2 seconds)
3. **Configure network if needed**:
   - If Ethernet is connected: Skip to step 4
   - If no Ethernet: Follow WiFi setup prompts
4. **Note the IP address**: The installer displays the IP address
5. **Run nixos-anywhere**: From your deployment machine, run the command shown

### WiFi Setup Example

```
Keystone Installer

⚠ No Ethernet connection detected

Would you like to set up WiFi?
> Yes, scan for WiFi networks
  No, I'll configure manually
```

After selecting "Yes":

```
Keystone Installer - WiFi Setup

Select a WiFi network:
> MyHomeNetwork
  CoffeeShopWiFi
  NeighborNetwork
```

After selecting a network:

```
Keystone Installer - WiFi Setup

Network: MyHomeNetwork
Enter password (press Enter when done):
> ********
```

After successful connection:

```
Keystone Installer

✓ WiFi Connected to MyHomeNetwork
Interface: wlan0 - IP: 192.168.1.150

Ready for Installation
From your deployment machine, run:
nixos-anywhere --flake .#your-config root@192.168.1.150
```

## Technical Details

### NetworkManager Integration

The installer uses NetworkManager (nmcli) for WiFi functionality:

- `nmcli device wifi rescan`: Scan for networks
- `nmcli device wifi list`: List available networks
- `nmcli device wifi connect`: Connect to a network

This ensures compatibility with a wide range of WiFi hardware.

### Auto-Start on Boot

The installer is configured to auto-start via systemd:

```nix
systemd.services.keystone-installer = {
  description = "Keystone Installer TUI";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" "NetworkManager.service" ];
  # Runs on TTY1 for easy access
};
```

### Network Interface Detection

The installer intelligently detects network interfaces:

- **Ethernet**: Interfaces starting with `eth`, `en`
- **WiFi**: Interfaces starting with `wl`, `wlan`
- **Loopback**: Automatically excluded from detection

## Troubleshooting

### Installer Doesn't Appear

If the installer TUI doesn't show on boot:

1. Switch to TTY1: Press `Ctrl+Alt+F1`
2. Check service status:
   ```bash
   systemctl status keystone-installer
   ```
3. View logs:
   ```bash
   journalctl -u keystone-installer
   ```

### WiFi Scanning Fails

If no WiFi networks appear:

1. Check if WiFi is enabled:
   ```bash
   nmcli radio wifi on
   ```
2. List WiFi devices:
   ```bash
   nmcli device status
   ```
3. Manually scan:
   ```bash
   nmcli device wifi rescan
   nmcli device wifi list
   ```

### Connection Issues

If WiFi connection fails:

1. Verify password is correct
2. Check signal strength in network list
3. Try manual connection:
   ```bash
   nmcli device wifi connect "NetworkName" password "password"
   ```
4. Check NetworkManager status:
   ```bash
   systemctl status NetworkManager
   ```

### Skip the Installer

If you prefer to configure networking manually:

1. Exit the installer (Ctrl+C)
2. Configure network manually with nmcli or ip commands
3. Start SSH if not running:
   ```bash
   systemctl start sshd
   ```

## Building Custom ISO

To build an ISO with the installer:

```bash
# Build ISO with SSH keys for remote access
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Or build without SSH keys (installer-only)
./bin/build-iso --no-ssh-key
```

The installer is automatically included in all Keystone ISOs.

## See Also

- [ISO Generation Guide](iso-generation.md)
- [Installation Guide](installation.md)
- [Testing Procedure](testing-procedure.md)
- [Ink Documentation](https://github.com/vadimdemedes/ink)
