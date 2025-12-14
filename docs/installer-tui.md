# Keystone Installer - Interactive TUI

The Keystone installer ISO includes an interactive Terminal User Interface (TUI) that provides multiple installation methods: remote installation via SSH, local installation directly on the machine, or cloning from an existing NixOS configuration repository.

## Overview

When you boot from the Keystone ISO, the installer automatically:

1. **Checks for Ethernet connectivity** - If an Ethernet cable is connected and has obtained an IP address, it displays the IP address
2. **Offers WiFi setup** - If no Ethernet connection is detected, it prompts you to configure WiFi
3. **Presents installation options** - Once network is configured, you can choose from three installation methods:
   - **Remote via SSH**: Traditional nixos-anywhere deployment from another machine
   - **Local installation**: Install NixOS directly on this machine with guided configuration
   - **Clone from repository**: Use an existing NixOS flake configuration from a git repository

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

### Local Installation

The local installation workflow guides you through:

1. **Disk Selection**: Choose which disk to install to
   - Shows all available disks with size and model information
   - Warns about disks containing existing data
   - Validates minimum disk size (8GB)

2. **Encryption Choice**: Select your security preference
   - **Encrypted (ZFS + LUKS + TPM2)**: Full disk encryption with automatic TPM2 unlock
   - **Unencrypted (ext4)**: Simple installation without encryption
   - TPM2 availability is automatically detected

3. **Host Configuration**: Set up your system
   - Hostname (validated per RFC 1123)
   - Username (validated per POSIX standards)
   - Password (with confirmation)
   - System type (Server or Client with Hyprland desktop)

4. **Configuration Generation**: Creates NixOS flake configuration
   - `~/nixos-config/flake.nix`: Main flake with Keystone inputs
   - `~/nixos-config/hosts/{hostname}/default.nix`: Host configuration
   - `~/nixos-config/hosts/{hostname}/disk-config.nix`: Disk configuration
   - `~/nixos-config/hosts/{hostname}/hardware-configuration.nix`: Auto-detected hardware

5. **Installation**: Runs nixos-install with the generated configuration

### Clone from Repository

Use an existing NixOS configuration:

1. Enter the git repository URL (HTTPS or SSH)
2. The installer clones the repository
3. Select from available host configurations in the `hosts/` directory
4. Installation proceeds with the selected configuration

### User-Friendly Interface

Built with [Ink](https://github.com/vadimdemedes/ink) (React for terminal UIs), the installer provides:

- Clean, modern terminal interface
- Loading spinners during network operations
- Clear error messages and retry options
- Keyboard navigation for all selections
- Back navigation (press Escape)
- Real-time input validation
- File operation transparency during installation

## Usage

### Typical Workflow

1. **Boot from USB/ISO**: Boot your target machine from the Keystone installer
2. **Wait for network check**: The installer automatically checks for connectivity (~2 seconds)
3. **Configure network if needed**:
   - If Ethernet is connected: Skip to step 4
   - If no Ethernet: Follow WiFi setup prompts
4. **Select "Continue to Installation"**: After network is configured
5. **Choose installation method**:
   - **Remote via SSH**: Note the IP address and run nixos-anywhere from another machine
   - **Local installation**: Follow the guided setup to install directly
   - **Clone from repository**: Enter your existing config repository URL

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

> Continue to Installation →
```

### Local Installation Example

After selecting "Local installation" from the method selection:

```
Keystone Installer - Disk Selection

Select a disk for installation:
> nvme0n1 - 500 GB (Samsung SSD 980 PRO)
  sda - 2 TB (WD Blue)
  ⚠️ sdb - 1 TB (Has existing data)

⚠️ = Disk contains existing data (will be erased)
```

After confirming disk selection:

```
Keystone Installer - Encryption

Choose disk encryption option:
> 🔒 Encrypted (ZFS + LUKS + TPM2) - Recommended
  🔓 Unencrypted (ext4) - Simple
```

After completing all configuration:

```
Keystone Installer - Installation Summary

┌─────────────────────────────────────────┐
│ Hostname: my-server                     │
│ Username: admin                         │
│ System Type: server                     │
│ Disk: nvme0n1 (500 GB)                  │
│ Encryption: ZFS + LUKS                  │
└─────────────────────────────────────────┘

> ✓ Start Installation
  ← Go back and make changes
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
