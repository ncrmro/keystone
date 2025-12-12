# PLAN: NixOS VM Test Framework for Installer

## Goal

Implement automated testing for the Keystone installer TUI using NixOS's VM test framework, allowing both interactive observation and CI/CD integration.

## Context

**Current State**: The installer TUI requires manual testing via `remote-viewer` which is time-consuming and error-prone.

**Desired State**: Automated tests that:
- Boot the installer ISO in a VM
- Send keystrokes to interact with the TUI
- Run through the full installation workflow
- Verify the installation succeeded
- Can be watched interactively or run headlessly in CI

**Related Files**:
- `modules/iso-installer.nix` - Installer ISO configuration
- `packages/keystone-installer-ui/` - TUI application
- `flake.nix` - Will need to expose the test

**NixOS VM Test Framework**:
- Uses QEMU under the hood
- Python test driver for scripting interactions
- Can send keystrokes, wait for text, run SSH commands
- Supports interactive mode with `--interactive` flag

## Tasks

### 1. Create basic VM test infrastructure
- [ ] Create `tests/` directory structure
- [ ] Create `tests/installer-test.nix` with basic VM configuration
- [ ] Configure VM with sufficient resources (8GB RAM, disk)
- [ ] Import installer ISO configuration

### 2. Implement test script for unencrypted installation
- [ ] Wait for installer TUI to load
- [ ] Send keystrokes to navigate through wizard:
  - [ ] Select "New Installation"
  - [ ] Enter hostname
  - [ ] Enter username
  - [ ] Enter password (twice)
  - [ ] Select disk
  - [ ] Choose unencrypted installation
  - [ ] Confirm and start installation
- [ ] Wait for installation to complete
- [ ] Verify success indicators

### 3. Add verification steps
- [ ] Check that /mnt is mounted after disko
- [ ] Verify flake.nix exists in target config
- [ ] Verify hardware-configuration.nix was generated
- [ ] Check nixos-install exit status

### 4. Expose test in flake.nix
- [ ] Add test to `checks.x86_64-linux`
- [ ] Create `driverInteractive` output for watching tests
- [ ] Document how to run tests

### 5. Add helper script for running tests
- [ ] Create `bin/test-installer` script
- [ ] Support `--interactive` flag for watching
- [ ] Support `--headless` flag for CI

### 6. (Optional) Add encrypted installation test
- [ ] Duplicate test for encrypted ZFS path
- [ ] Handle password entry for encryption
- [ ] Verify ZFS pool creation

## Implementation Notes

### Test Script Structure
```python
# Basic structure of testScript
machine.wait_for_unit("keystone-installer.service")
machine.wait_for_text("Welcome to Keystone")  # Wait for TUI

# Navigate wizard
machine.send_key("ret")  # Select option
machine.send_chars("my-hostname")
machine.send_key("ret")
# ... continue through wizard

# Wait for completion
machine.wait_for_text("Installation complete")

# Verify results
machine.succeed("test -d /mnt/boot")
machine.succeed("test -f /mnt/home/*/nixos-config/flake.nix")
```

### Running Tests
```bash
# Build and run headlessly
nix build .#checks.x86_64-linux.installer-test

# Run interactively (watch the VM)
nix build .#checks.x86_64-linux.installer-test.driverInteractive
./result/bin/nixos-test-driver --interactive

# In the Python REPL
>>> start_all()
>>> test_script()  # Or step through manually
```

### Key Considerations
- The TUI uses Ink (React for CLI) - need to understand exact text output for `wait_for_text`
- May need to add small delays between keystrokes
- Serial console vs graphical console - tests typically use serial
- Need to handle the case where installation takes several minutes

## Progress

- [x] Task 1: Create basic VM test infrastructure
- [x] Task 2: Implement test script
- [x] Task 3: Add verification steps
- [x] Task 4: Expose in flake.nix
- [x] Task 5: Add helper script
- [ ] Task 6: (Optional) Encrypted test

## Implementation Summary

### Files Created/Modified

1. **`tests/installer-test.nix`** - Main VM test configuration
   - Configures VM with 8GB RAM, 4 cores, UEFI boot
   - Adds a 20GB empty disk for installation target
   - Sets up the installer service and required packages
   - Contains Python test script for TUI interaction

2. **`flake.nix`** - Added checks output
   - Exposes test at `checks.x86_64-linux.installer-test`
   - Automatically creates `driverInteractive` for interactive mode

3. **`bin/test-installer`** - Helper script
   - `--interactive` flag for watching tests
   - `--headless` flag for CI (default)
   - `--build-only` flag to only build without running

### Usage

```bash
# Run test headlessly (default)
./bin/test-installer

# Watch test interactively
./bin/test-installer --interactive

# In interactive mode REPL:
>>> start_all()      # Start VM
>>> test_script()    # Run full test
>>> installer.shell_interact()  # Drop into VM shell
```

### Test Flow

1. Boot VM and wait for multi-user.target
2. Start keystone-installer service
3. Wait for "Network Connected" screen
4. Navigate: Continue → Local installation → Select disk → Confirm
5. Select unencrypted installation
6. Enter hostname, username, password
7. Select server type → Review summary → Start installation
8. Wait for "Installation Complete" (10 min timeout)
9. Verify: /mnt mounted, flake.nix exists, hardware-config exists
