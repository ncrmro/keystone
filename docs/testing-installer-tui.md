# Testing the Keystone Installer TUI

This guide explains how to test the interactive installer TUI.

## Prerequisites

- Working Nix installation with flakes enabled
- SSH keys for remote access (optional but recommended)

## Building the ISO

First, build the ISO with the installer included:

```bash
# Build with SSH keys for remote access
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Or build without SSH keys (installer-only mode)
./bin/build-iso --no-ssh-key
```

### First Build: Get npmDepsHash

On the first build attempt, the npm dependencies hash needs to be determined:

```bash
nix build .#keystone-installer-ui
```

The build will fail with an error message showing the expected hash:

```
error: hash mismatch in fixed-output derivation '/nix/store/...':
  specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  got:        sha256-<actual-hash-here>
```

Copy the actual hash and update `packages/keystone-installer-ui/default.nix`:

```nix
npmDepsHash = "sha256-<actual-hash-here>";
```

Then rebuild:

```bash
nix build .#keystone-installer-ui
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

## VM Testing

### Option 1: Using bin/virtual-machine (Recommended)

Create a VM for testing:

```bash
# Create and start VM
./bin/virtual-machine --name installer-test --start

# View the console (installer should appear on TTY1)
remote-viewer $(virsh domdisplay installer-test)
```

### Option 2: Manual QEMU Testing

```bash
# After building the ISO
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cdrom result/iso/keystone-installer.iso \
  -boot d \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

## Testing Scenarios

### Scenario 1: Ethernet Connection (Happy Path)

1. Boot VM from ISO
2. Wait for network to initialize (~2 seconds)
3. Installer should display:
   - Green checkmark: "Network Connected"
   - Interface name and IP address
   - Installation command with IP

**Expected Result**: Installer displays IP address and installation instructions immediately.

### Scenario 2: No Network (WiFi Setup Path)

For this scenario, you need to boot without network or disable Ethernet in the VM:

```bash
# Boot without network
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cdrom result/iso/keystone-installer.iso \
  -boot d
  # No -netdev parameter
```

1. Boot VM from ISO
2. Installer detects no Ethernet connection
3. Prompts: "Would you like to set up WiFi?"
4. Select "Yes, scan for WiFi networks"
5. (In VM without WiFi, this will show no networks)

**Expected Result**: Installer offers WiFi setup but gracefully handles no WiFi hardware.

### Scenario 3: Manual Network Configuration

1. Boot VM from ISO
2. When prompted for WiFi setup, select "No, I'll configure manually"
3. Installer shows placeholder IP (or allows manual continuation)

**Expected Result**: User can skip WiFi setup and configure manually.

## Manual Testing Steps

If you want to test the installer components manually:

### Test Network Detection

```bash
# After booting the ISO
keystone-installer  # Run the installer

# Or test network utilities directly
# (These require the TypeScript to be built and Node.js available)
```

### Test WiFi Scanning

```bash
# On a system with WiFi hardware
nmcli device wifi rescan
nmcli device wifi list
```

### Test SystemD Service

```bash
# Check service status
systemctl status keystone-installer

# View logs
journalctl -u keystone-installer -f

# Restart installer
systemctl restart keystone-installer
```

## Verification Checklist

After booting the installer ISO:

- [ ] Installer appears on TTY1 automatically
- [ ] Network check completes within 3 seconds
- [ ] Ethernet connections are detected correctly
- [ ] IP addresses are displayed accurately
- [ ] WiFi option appears when no Ethernet
- [ ] Installation command is properly formatted
- [ ] IP address in command matches detected IP
- [ ] Service restarts on failure
- [ ] Logs are accessible via journalctl

## Troubleshooting Tests

### Installer Doesn't Start

```bash
# Check systemd service
systemctl status keystone-installer

# Check for Node.js
which node

# Check for package
which keystone-installer

# View service logs
journalctl -u keystone-installer --no-pager
```

### Network Detection Issues

```bash
# Manually test network detection
ip -4 -o addr show

# Check NetworkManager
systemctl status NetworkManager
nmcli device status
```

### Build Issues

```bash
# Verify package builds
nix build .#keystone-installer-ui

# Check for TypeScript errors
cd packages/keystone-installer-ui
npm install
npm run build
```

## Integration Testing

Full integration test with nixos-anywhere:

1. Build ISO with SSH keys
2. Boot VM from ISO
3. Note IP address from installer
4. Deploy test configuration:
   ```bash
   nixos-anywhere --flake .#test-server root@<installer-ip>
   ```
5. Verify deployment succeeds

## Performance Expectations

- Boot to installer display: ~10-20 seconds
- Network check: ~2 seconds
- WiFi scan: ~3-5 seconds
- WiFi connection: ~3-5 seconds

## Common Issues and Solutions

### "Cannot find module 'ink'"

The npm dependencies weren't installed correctly in the Nix derivation. Verify `npmDepsHash` is correct.

### WiFi Scanning Returns No Networks

- WiFi hardware may not be available in VM
- NetworkManager may need time to initialize
- Try manual scan: `nmcli device wifi rescan`

### Service Restarts Continuously

Check logs for errors:
```bash
journalctl -u keystone-installer -n 50
```

Common causes:
- Missing Node.js
- Missing npm dependencies  
- TypeScript compilation errors
- NetworkManager not running

## CI/CD Testing

For automated testing (future enhancement):

```bash
# Build ISO in CI
nix build .#iso

# Extract ISO size and metadata
ls -lh result/iso/*.iso

# Verify installer package builds
nix build .#keystone-installer-ui
```

## Documentation

See also:
- [Installer TUI Documentation](installer-tui.md)
- [Installation Guide](installation.md)
- [Testing Procedure](testing-procedure.md)
