# TODO: Serial Console Setup for Deployment Testing

**Date**: 2025-10-28
**Feature**: 002-nixos-anywhere-vm-install
**Issue**: GTK window not appearing for password prompt during deployment test
**Solution**: Switch to serial console output in terminal

## Context

**Relevant Specifications**:
- `specs/002-nixos-anywhere-vm-install/spec.md` - Feature specification
- `specs/002-nixos-anywhere-vm-install/tasks.md` - Task breakdown (currently at T022i)
- `specs/002-nixos-anywhere-vm-install/quickstart.md` - Deployment procedures
- `specs/002-nixos-anywhere-vm-install/TROUBLESHOOTING.md` - Troubleshooting guide

**Current Status**:
- Deployment test running with `bin/test-deployment --hard-reset`
- System successfully deployed and rebooted
- Waiting at password prompt for credstore unlock
- GTK window (display="gtk") not visible to user
- SSH timing out because system can't boot past password prompt

**Problem**:
The QEMU GTK window that should show the password prompt is either:
- Not opening
- Hidden/minimized and cannot be found
- Has display configuration issues

**Solution**:
Switch from GTK graphical window to serial console in terminal

## Implementation Tasks

### 1. Clean Up Existing Processes and Artifacts
**Status**: Pending
**Files**: N/A
**Commands**:
```bash
# Kill test script and VM
pkill -9 -f "test-deployment"
pkill -9 -f "qemu.*server"
pkill -9 -f "quickemu"

# Clean VM artifacts
rm -rf vms/server/
```

### 2. Modify VM Configuration for Serial Console
**Status**: Pending
**File**: `vms/server.conf`
**Change**:
```bash
# Current configuration (line 8):
display="gtk"

# New configuration:
display="none"
serial="mon:stdio"  # Sends console output to terminal stdin/stdout
```

**Reference**: `specs/002-nixos-anywhere-vm-install/quickstart.md` Section 6 (First Boot)

### 3. Update Test Script Password Prompt Instructions
**Status**: Pending
**File**: `bin/test-deployment`
**Location**: Lines 267-291 (password prompt section)
**Change**: Update instructions to reflect serial console instead of GTK window

**Current instructions mention**:
```
1. Look for the QEMU window (should be visible on your screen)
```

**Should say**:
```
1. The password prompt will appear in THIS TERMINAL (no separate window)
```

**Reference**: `specs/002-nixos-anywhere-vm-install/tasks.md` Task T022i

### 4. Start VM with Serial Console
**Status**: Pending
**Command**: `make vm-server`
**Expected**: Boot messages will appear in terminal where command is run
**Reference**: `Makefile` vm-server target

### 5. Wait for ISO Boot and SSH
**Status**: Pending
**Verification**:
```bash
# SSH will be available when:
ssh -p 22220 -o ConnectTimeout=3 root@localhost 'echo ready'
```
**Expected Time**: 30-60 seconds after VM start
**Reference**: `specs/002-nixos-anywhere-vm-install/DEPLOYMENT-TIMELINE.md` Phase 1

### 6. Run Deployment
**Status**: Pending
**Command**: Re-run `./bin/test-deployment --hard-reset` OR manually run deployment steps
**Expected**: Deployment progress shown in terminal
**Reference**: `specs/002-nixos-anywhere-vm-install/tasks.md` Tasks T007-T015

### 7. Handle Password Prompt (In Terminal)
**Status**: Pending
**Expected Terminal Output**:
```
[    5.123] systemd-cryptsetup[456]: Please enter passphrase for disk /dev/zvol/rpool/credstore-enc:
```
**Action**: Type password directly in terminal (no echo - normal password behavior)
**Reference**: `specs/002-nixos-anywhere-vm-install/quickstart.md` Section 6

### 8. Verify System Boot
**Status**: Pending
**Tasks**: T016-T022 from tasks.md
**Checks**:
- [ ] T016: System reboots automatically after deployment
- [ ] T017: SSH access works with configured keys
- [ ] T018: SSH service running (`systemctl status sshd`)
- [ ] T019: ZFS pool mounted (`zpool status rpool`)
- [ ] T020: Encryption enabled (`zfs get encryption rpool/crypt`)
- [ ] T021: Root filesystem accessible (`df -h /`)
- [ ] T022: Document any issues encountered

**Reference**: `specs/002-nixos-anywhere-vm-install/tasks.md` Lines 76-82

### 9. Run Verification Script
**Status**: Pending
**Task**: T033 from tasks.md
**Command**:
```bash
./scripts/verify-deployment.sh test-server localhost --ssh-port 22220
```
**Expected**: All checks pass (PASS count > 0, FAIL count = 0)
**Reference**: `scripts/verify-deployment.sh` and `specs/002-nixos-anywhere-vm-install/tasks.md` Task T033

### 10. Mark Tasks Complete
**Status**: Pending
**File**: `specs/002-nixos-anywhere-vm-install/tasks.md`
**Tasks to Mark**:
- [x] T022i: Test complete deployment with wrapper script
- [x] T016-T022: US1 verification tasks
- [x] T033: Test verification script
**Reference**: `specs/002-nixos-anywhere-vm-install/tasks.md` Lines 105, 76-82, 145

## Technical Details

### Why Serial Console Instead of GTK?

**Benefits**:
1. **No window management issues** - everything in one terminal
2. **Better for automation** - can script interactions
3. **Easier troubleshooting** - can see all output in scrollback
4. **No keyboard grab issues** - normal terminal interaction
5. **Copy/paste works** - standard terminal functionality

**How It Works**:
- QEMU redirects VM's serial port (ttyS0) to host's stdin/stdout
- VM kernel configured to use serial console as primary console
- All boot messages, login prompts, and output appear in terminal
- User input goes directly to VM

**Configuration Details**:
```bash
# In vms/server.conf:
serial="mon:stdio"

# This translates to QEMU args:
-serial mon:stdio

# Which means:
# - "serial": Use serial port
# - "mon": Enable QEMU monitor multiplexed with console
# - "stdio": Connect to host terminal stdin/stdout
```

### Alternative Serial Options

If `mon:stdio` doesn't work, try:
```bash
# Option 1: Simple stdio (no monitor)
serial="stdio"

# Option 2: PTY (pseudo-terminal)
serial="pty"
# Then connect with: screen /dev/pts/X

# Option 3: Socket file
serial="unix:vms/server/serial.sock,server,nowait"
# Then connect with: socat - UNIX-CONNECT:vms/server/serial.sock
```

**Reference**: `specs/002-nixos-anywhere-vm-install/TROUBLESHOOTING.md` Serial Console section

## Success Criteria

### Deployment Test Success:
- [ ] VM boots from ISO with serial console visible in terminal
- [ ] SSH becomes available (can connect on port 22220)
- [ ] nixos-anywhere deploys successfully
- [ ] System reboots and shows password prompt in terminal
- [ ] User enters password and system boots
- [ ] SSH access works to deployed system
- [ ] ZFS pool is mounted and healthy
- [ ] Encryption is active
- [ ] Verification script passes all checks

### Implementation Complete When:
- [ ] All T016-T022 tasks marked complete in tasks.md
- [ ] T033 (verification script test) marked complete
- [ ] No blocking issues remain for deployment testing
- [ ] Documentation updated if any process changes needed

**Overall Progress**: 67/76 tasks (88%) → Target: 73/76 tasks (96%)

## Notes

- **Total deployment time**: 10-15 minutes expected
- **Password prompt appears**: ~5-10 minutes after starting deployment
- **Boot after password**: ~1-2 minutes to SSH availability
- **Keep this terminal open**: All VM interaction will be here

## References

**Key Files**:
- `vms/server.conf` - VM configuration
- `bin/test-deployment` - Deployment test script
- `scripts/verify-deployment.sh` - Verification script
- `Makefile` - VM management targets

**Documentation**:
- `specs/002-nixos-anywhere-vm-install/spec.md` - Feature requirements
- `specs/002-nixos-anywhere-vm-install/tasks.md` - Task breakdown and status
- `specs/002-nixos-anywhere-vm-install/quickstart.md` - Usage guide
- `specs/002-nixos-anywhere-vm-install/DEPLOYMENT-TIMELINE.md` - Timing expectations
- `specs/002-nixos-anywhere-vm-install/TROUBLESHOOTING.md` - Common issues

## Current Blockers

None - ready to proceed with serial console setup.

## Next Action

Execute Task 1: Clean up existing processes and artifacts
