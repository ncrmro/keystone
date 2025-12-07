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
4. Select "Continue to Installation"
5. Method selection screen should appear

**Expected Result**: Installer displays IP address and allows continuing to method selection.

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

### Scenario 3: Local Installation (Full Flow)

1. Boot VM from ISO with network
2. Continue to method selection
3. Select "Local installation"
4. **Disk Selection**:
   - Verify disks are listed with size and model
   - Disks with data show warning icon
   - Select a disk
5. **Disk Confirmation**:
   - Warning about data erasure displayed
   - Confirm selection
6. **Encryption Choice**:
   - Select encrypted or unencrypted
   - If encrypted and no TPM2, warning should appear
7. **Hostname Input**:
   - Enter valid hostname (e.g., "test-server")
   - Invalid hostnames should show error
8. **Username Input**:
   - Enter valid username (e.g., "admin")
   - Reserved names should be rejected
9. **Password Input**:
   - Enter and confirm password
   - Mismatched passwords should show error
10. **System Type**:
    - Select Server or Client
11. **Summary**:
    - Verify all settings displayed correctly
    - Start installation

**Expected Result**: Installation proceeds through all phases with progress display.

### Scenario 4: Clone from Repository

1. Boot VM from ISO with network
2. Continue to method selection
3. Select "Clone from repository"
4. Enter a valid git URL (e.g., `https://github.com/ncrmro/keystone`)
5. Wait for clone to complete
6. Select a host from the list (if available)
7. Verify summary and start installation

**Expected Result**: Repository is cloned and hosts are available for selection.

### Scenario 5: Dev Mode Testing

Test the installer without making real changes:

```bash
# Build and run in dev mode
cd packages/keystone-installer-ui
npm run build
DEV_MODE=1 node dist/index.js
```

**Expected Result**:
- "[DEV MODE]" indicator shown in header
- Disks detected but operations simulated
- Config files written to /tmp/keystone-dev/
- No actual formatting or installation

### Scenario 6: Back Navigation

1. Navigate to any screen past method selection
2. Press Escape key
3. Verify return to previous screen
4. Data entered should be preserved

**Expected Result**: Escape key navigates back without losing data.

### Scenario 7: No Disks Detected

1. Boot VM with no virtual disks attached
2. Select "Local installation"
3. Disk selection screen should show:
   - "No suitable disks found" message
   - Hardware check suggestion
   - Option to refresh or go back

**Expected Result**: Graceful handling with user guidance.

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

### Network Setup
- [ ] Installer appears on TTY1 automatically
- [ ] Network check completes within 3 seconds
- [ ] Ethernet connections are detected correctly
- [ ] IP addresses are displayed accurately
- [ ] WiFi option appears when no Ethernet
- [ ] "Continue to Installation" button appears after network setup

### Method Selection
- [ ] Three installation methods displayed
- [ ] Remote method shows SSH command with correct IP
- [ ] Local method transitions to disk selection
- [ ] Clone method transitions to repository URL input

### Local Installation Flow
- [ ] Disks detected and listed correctly
- [ ] Warning icons shown for disks with data
- [ ] Disk confirmation shows correct details
- [ ] Encryption options displayed
- [ ] TPM2 warning shown when TPM unavailable
- [ ] Hostname validation works (RFC 1123)
- [ ] Username validation works (POSIX)
- [ ] Password confirmation required
- [ ] System type selection works
- [ ] Summary shows all configuration
- [ ] Installation progress displayed
- [ ] File operations logged and shown
- [ ] Complete screen with reboot option

### Navigation
- [ ] Escape key returns to previous screen
- [ ] Data preserved when going back
- [ ] Cannot go back during installation

### Error Handling
- [ ] No disks shows helpful message
- [ ] Invalid input shows specific error
- [ ] Installation errors show suggestion
- [ ] Retry option available on error

### General
- [ ] Service restarts on failure
- [ ] Logs are accessible via journalctl
- [ ] DEV_MODE works without real operations

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
