# Keystone Installer UI

A Terminal User Interface (TUI) installer for Keystone using [Ink](https://github.com/vadimdemedes/ink).

## Features

- **Automatic Network Detection**: Checks for Ethernet connectivity on boot
- **WiFi Configuration**: Interactive WiFi setup if no Ethernet connection is detected
- **NetworkManager Integration**: Uses nmcli for WiFi scanning and connection
- **User-Friendly TUI**: Built with React and Ink for a modern terminal interface

## How It Works

1. **Network Check**: On ISO boot, the installer checks for an active Ethernet connection with an IP address
2. **WiFi Setup**: If no Ethernet is found, it prompts to scan for WiFi networks
3. **Network Selection**: User selects from available WiFi networks
4. **Authentication**: User enters the WiFi password
5. **Connection**: Connects to WiFi and displays the IP address
6. **Ready for Deployment**: Shows nixos-anywhere command with the obtained IP address

## Development

### Prerequisites

- Node.js 18+
- npm

### Building

```bash
# Install dependencies
npm install

# Build TypeScript to JavaScript
npm run build

# Run in development mode
npm run dev
```

### Testing Locally

You can test the installer UI locally (note: network commands require root):

```bash
npm run dev
```

## Nix Package

This package is built with `buildNpmPackage`. To get the correct `npmDepsHash`:

1. Try to build the package:
```bash
nix build .#keystone-installer-ui
```

2. The error message will show the expected hash. Copy it and update `default.nix`:
```nix
npmDepsHash = "sha256-..."; # Replace with the hash from the error
```

3. Build again to verify:
```bash
nix build .#keystone-installer-ui
```

## Integration with ISO

The installer is automatically included in the Keystone ISO and starts on boot via systemd service.

### Auto-Start Service

The installer runs on TTY1 and is managed by systemd:

```nix
systemd.services.keystone-installer = {
  description = "Keystone Installer TUI";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" "NetworkManager.service" ];
  # ... service configuration
};
```

## Architecture

### Files

- `src/index.tsx`: Entry point that renders the App component
- `src/App.tsx`: Main application component with state management and UI screens
- `src/network.ts`: Network utilities (interface detection, WiFi scanning, connection)

### Dependencies

- **ink**: React-based TUI framework
- **ink-text-input**: Text input component
- **ink-select-input**: Selection menu component
- **ink-spinner**: Loading spinner component
- **react**: UI framework

## Troubleshooting

### No WiFi Networks Found

If WiFi scanning fails:
- Ensure wireless drivers are loaded
- Check if the wireless interface is enabled: `nmcli radio wifi`
- Manually scan: `nmcli device wifi rescan`

### Connection Failures

If WiFi connection fails:
- Verify the password is correct
- Check signal strength: `nmcli device wifi list`
- View NetworkManager logs: `journalctl -u NetworkManager`

### Installer Not Starting

If the installer doesn't auto-start on boot:
- Check systemd service status: `systemctl status keystone-installer`
- View service logs: `journalctl -u keystone-installer`
- Manually start: `systemctl start keystone-installer`

## License

MIT
