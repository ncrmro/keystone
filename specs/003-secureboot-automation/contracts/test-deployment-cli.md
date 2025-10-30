# Contract: test-deployment CLI

**Feature**: 003-secureboot-automation
**Date**: 2025-10-29
**Type**: Command-Line Interface Contract

## Overview

This document defines the command-line interface contract for the `bin/test-deployment` script with Secure Boot automation extensions.

---

## Command Line Interface

### Synopsis

```bash
./bin/test-deployment [OPTIONS]
```

### Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--rebuild-iso` | Rebuild the Keystone installer ISO before testing | false | No |
| `--hard-reset` | Force kill VM and clean all artifacts before testing | false | No |
| `--skip-secureboot` | Skip Secure Boot enrollment and verification phases | false | No |
| `--help`, `-h` | Display help message and exit | - | No |

### Examples

```bash
# Standard test run with Secure Boot
./bin/test-deployment

# Clean test from scratch with ISO rebuild
./bin/test-deployment --rebuild-iso --hard-reset

# Test without Secure Boot (for unsupported platforms)
./bin/test-deployment --skip-secureboot

# Full clean rebuild
./bin/test-deployment --rebuild-iso --hard-reset
```

---

## Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | All phases completed successfully |
| 1 | Failure | One or more phases failed |
| 130 | Interrupted | User interrupted with Ctrl+C |

---

## Execution Phases

The script executes the following phases in order:

### Phase 1: Cleanup (Conditional)

**Trigger**: `--hard-reset` flag or graceful stop

**Actions**:
- Stop running VM processes (SIGTERM or SIGKILL)
- Clean VM artifacts (disk, OVMF_VARS, logs, sockets)
- Restore ISO line in VM configuration

**Expected Duration**: 5-10 seconds

**Success Criteria**:
- All VM processes terminated
- Artifacts removed or graceful continuation

### Phase 2: ISO Build (Conditional)

**Trigger**: `--rebuild-iso` flag

**Actions**:
- Build Keystone installer ISO with SSH key injection
- Place ISO in `vms/keystone-installer.iso`

**Expected Duration**: 2-5 minutes

**Success Criteria**:
- ISO file created successfully
- Build completes without errors

### Phase 3: VM Start

**Actions**:
- Start VM from installer ISO using `make vm-server`
- Wait 30 seconds for boot

**Expected Duration**: 30-45 seconds

**Success Criteria**:
- QEMU process started
- VM boots to installer environment

### Phase 4: SSH Wait

**Actions**:
- Poll SSH connectivity on port 22220
- Maximum 10 attempts with 3-second delays

**Expected Duration**: 10-30 seconds

**Success Criteria**:
- SSH connection established
- Responds to `echo ready` command

### Phase 5: nixos-anywhere Deployment

**Actions**:
- Deploy NixOS configuration using nixos-anywhere
- Install to `/dev/vda` with ZFS encryption
- Manual cleanup and reboot

**Expected Duration**: 5-10 minutes

**Success Criteria**:
- Deployment completes without errors
- ZFS pool created and encrypted
- System ready for reboot

### Phase 6: Reboot to Installed System

**Actions**:
- Remove ISO from VM configuration
- Kill VM and remove old startup script
- Restart VM to boot from disk
- Auto-send LUKS password via serial console

**Expected Duration**: 40-60 seconds

**Success Criteria**:
- VM reboots successfully
- LUKS unlocked automatically
- System boots to installed OS

### Phase 7: Secure Boot Capability Check (NEW)

**Trigger**: Not `--skip-secureboot`

**Actions**:
- Check if `/sys/firmware/efi` exists
- Check if Secure Boot variables present
- Detect Secure Boot firmware support

**Expected Duration**: 5 seconds

**Success Criteria**:
- UEFI mode confirmed
- Secure Boot variables accessible

**Failure Handling**:
- If unsupported: Log warning, skip remaining Secure Boot phases
- Continue with final verification

### Phase 8: Secure Boot Key Enrollment (NEW)

**Trigger**: Secure Boot capability detected AND not `--skip-secureboot`

**Actions**:
- Verify sbctl keys exist in `/var/lib/sbctl`
- Run `sbctl status` to check current state
- Enroll keys if `enrollKeys = true` in config (automatic)
- OR manually trigger enrollment via SSH

**Expected Duration**: 10-15 seconds

**Success Criteria**:
- Keys enrolled successfully
- Setup Mode transitions to User Mode
- `sbctl status` shows enrollment complete

**Failure Handling**:
- Log enrollment failure details
- Mark phase as failed
- Skip Secure Boot verification
- Continue to final verification

### Phase 9: Secure Boot Reboot (NEW)

**Trigger**: Successful key enrollment

**Actions**:
- Trigger system reboot
- Wait for system to come back online
- Re-establish SSH connection

**Expected Duration**: 60-90 seconds

**Success Criteria**:
- System reboots successfully
- SSH reconnects
- System boots with enrolled keys

### Phase 10: Secure Boot Verification (NEW)

**Trigger**: Successful reboot after enrollment

**Actions**:
- Check Setup Mode status (should be disabled)
- Check Secure Boot enabled status
- Verify via `bootctl status`
- Verify via `sbctl status`
- Verify via sysfs variables
- Verify boot files signed with `sbctl verify`

**Expected Duration**: 10-15 seconds

**Success Criteria**:
- All verification checks pass
- Secure Boot reported as enabled
- Boot components properly signed

**Failure Handling**:
- Report specific check that failed
- Log detailed error information
- Mark phase as failed (non-fatal)

### Phase 11: Final Verification

**Actions**:
- Verify SSH connectivity
- Check hostname
- Verify ZFS pool status
- Check SSH service status

**Expected Duration**: 30 seconds

**Success Criteria**:
- All basic checks pass
- System fully operational

---

## Output Format

### Progress Indicators

```
[N/M] Phase Description
```

Where:
- N = Current step number
- M = Total steps for this test run
- Phase Description = Human-readable phase name

### Status Messages

- `✓` Success (green)
- `✗` Error (red)
- `⚠` Warning (yellow)
- `ℹ` Info (cyan)

### Example Output

```
============================================================
Keystone Deployment Test
============================================================
Rebuild ISO: False
Hard Reset: False

[1/8] Starting VM from ISO
ℹ Starting VM using make vm-server...
ℹ Waiting for VM to boot (30 seconds)...
✓ VM started successfully

[2/8] Waiting for SSH access
  Attempt 1/10...
  Attempt 2/10...
✓ SSH is ready

[3/8] Deploying with nixos-anywhere
ℹ This will take 5-10 minutes...
✓ Deployment phase completed!

[4/8] Removing ISO and rebooting to disk
ℹ Sending password to serial console...
✓ Password sent to serial console
ℹ Waiting for system to finish booting (25 seconds)...

[5/8] Checking Secure Boot capability
ℹ Verifying UEFI mode and Secure Boot support...
✓ UEFI mode confirmed
✓ Secure Boot variables accessible

[6/8] Enrolling Secure Boot keys
ℹ Enrolling keys via sbctl...
✓ Keys enrolled successfully
✓ Setup Mode disabled (User Mode active)

[7/8] Verifying Secure Boot
ℹ Running Secure Boot verification checks...
✓ Setup Mode status: disabled
✓ Secure Boot enabled
✓ bootctl confirms Secure Boot
✓ sbctl confirms Secure Boot
✓ Boot files properly signed

[8/8] Verifying deployment
ℹ Waiting for deployed system to finish booting (30 seconds)...
ℹ Running verification checks...
✓ SSH connectivity
✓ Hostname
✓ ZFS pool
✓ SSH service

Passed: 4, Failed: 0

============================================================
✓ All tests passed!
============================================================

SSH to deployed server:

Remove old host key (if you get host key verification failed):
  ssh-keygen -R '[localhost]:22220'

SSH with normal key checking:
  ssh -p 22220 root@localhost

SSH ignoring host key verification:
  ssh -p 22220 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost
```

---

## Environment Requirements

### Host System

- NixOS or Linux with Nix installed
- QEMU/KVM installed and accessible
- SSH client available
- socat installed (for serial console communication)
- Sufficient resources:
  - CPU: 2+ cores recommended
  - RAM: 8GB+ available
  - Disk: 30GB+ free space

### VM Configuration

- Valid `vms/server.conf` (created from `vms/server.conf.example`)
- OVMF firmware with Secure Boot support
- Writable OVMF_VARS.fd for NVRAM persistence
- Virtio disk controller (/dev/vda)

### Network

- Port 22220 available for SSH forwarding
- No firewall blocking localhost connections

---

## Error Scenarios

### VM Start Failure

**Symptoms**:
```
[1/8] Starting VM from ISO
✗ Failed to start VM
```

**Possible Causes**:
- QEMU not installed
- VM config file missing
- Disk already in use
- Insufficient permissions

**Resolution**:
- Check `make vm-server` output for errors
- Verify `vms/server.conf` exists
- Try `--hard-reset` flag

### SSH Timeout

**Symptoms**:
```
[2/8] Waiting for SSH access
  Attempt 10/10...
✗ SSH never became available
```

**Possible Causes**:
- VM failed to boot
- Network configuration issue
- SSH keys not injected in ISO
- Port 22220 already in use

**Resolution**:
- Check VM console for boot errors
- Verify SSH key in ISO: `--rebuild-iso`
- Check port availability: `lsof -i :22220`

### Deployment Failure

**Symptoms**:
```
[3/8] Deploying with nixos-anywhere
✗ Deployment failed - check output above
```

**Possible Causes**:
- Disk partitioning errors
- Network issues during package download
- Invalid NixOS configuration
- Insufficient disk space

**Resolution**:
- Review nixos-anywhere output
- Check VM disk size (should be 20GB+)
- Verify flake configuration

### Secure Boot Not Supported

**Symptoms**:
```
[5/8] Checking Secure Boot capability
⚠ UEFI Secure Boot not supported on this platform
ℹ Skipping Secure Boot enrollment and verification
```

**Causes**:
- VM firmware doesn't support Secure Boot
- Booted in Legacy BIOS mode instead of UEFI
- OVMF without Secure Boot build

**Resolution**:
- Update VM configuration to use OVMF with Secure Boot
- Ensure `virtualisation.useEFIBoot = true` in config
- This is not a failure - script continues gracefully

### Enrollment Failure

**Symptoms**:
```
[6/8] Enrolling Secure Boot keys
✗ Failed to enroll Secure Boot keys
```

**Possible Causes**:
- Firmware not in Setup Mode
- Keys not generated
- Permission issues

**Resolution**:
- Check `sbctl status` output for details
- Verify keys exist in `/var/lib/sbctl`
- May require manual firmware reset to Setup Mode

### Verification Failure

**Symptoms**:
```
[7/8] Verifying Secure Boot
✓ Setup Mode status: disabled
✗ Secure Boot enabled
```

**Causes**:
- Keys enrolled but Secure Boot not enabled in firmware
- OVMF configuration issue

**Resolution**:
- This indicates enrollment succeeded but activation didn't
- May require manual UEFI settings adjustment
- Not a blocking failure for other tests

---

## Integration Points

### Files Read

- `vms/server.conf` - VM configuration
- `~/.ssh/id_ed25519.pub` - SSH public key for ISO (if `--rebuild-iso`)

### Files Written

- `vms/keystone-installer.iso` - Built installer ISO (if `--rebuild-iso`)
- `vms/server/disk.qcow2` - VM disk image
- `vms/server/OVMF_VARS.fd` - UEFI NVRAM variables
- `vms/server/*.log` - VM runtime logs

### Files Modified

- `vms/server.conf` - ISO line commented/uncommented
- `vms/server/server.sh` - Regenerated on VM restarts

### External Commands

- `make vm-server` - Start VM
- `nix run nixpkgs#nixos-anywhere` - Deploy NixOS
- `ssh` - Remote command execution
- `socat` - Serial console communication
- `pgrep`, `pkill` - Process management

---

## Backward Compatibility

### Existing Functionality Preserved

All existing test-deployment functionality remains unchanged:
- VM lifecycle management
- ISO building
- nixos-anywhere deployment
- ZFS encryption testing
- Serial unlock automation
- Post-deployment verification

### New Optional Behavior

Secure Boot phases are additive:
- Automatically attempted when Secure Boot supported
- Gracefully skipped when unsupported
- Can be explicitly disabled with `--skip-secureboot`
- Failures in Secure Boot phases don't fail entire test (logged as warnings)

### Breaking Changes

None. The new functionality is purely additive.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2025-10-29 | Added Secure Boot automation phases (003-secureboot-automation) |
| 1.0.0 | 2025-10-16 | Initial automated deployment testing (002-nixos-anywhere-vm-install) |
