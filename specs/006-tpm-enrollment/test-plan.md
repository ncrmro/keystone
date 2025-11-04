# Manual Test Plan: TPM Enrollment

**Feature**: 006-tpm-enrollment
**Version**: 1.0
**Date**: 2025-11-03
**Testing Method**: Manual VM testing with bin/virtual-machine

## Overview

This test plan validates the TPM enrollment feature through manual testing on VMs with TPM 2.0 emulation. All user stories must be independently tested and verified.

---

## Test Environment Setup

### Prerequisites

```bash
# Ensure bin/virtual-machine script is available
$ ls -la bin/virtual-machine

# Build Keystone ISO with TPM enrollment module enabled
$ nix build .#iso

# Or use bin/build-iso
$ ./bin/build-iso
```

### Create Test VM

```bash
# Create VM with TPM emulation (automatically enabled by bin/virtual-machine)
$ ./bin/virtual-machine --name tpm-test-vm --start

# Connect to graphical console
$ remote-viewer $(virsh domdisplay tpm-test-vm)

# Or serial console
$ virsh console tpm-test-vm
```

### Deploy Test Configuration

Create a test configuration in `vms/tpm-test-vm/configuration.nix`:

```nix
{
  imports = [
    ../../modules/server
    ../../modules/disko-single-disk-root
    ../../modules/secure-boot
    ../../modules/tpm-enrollment  # Enable TPM enrollment module
  ];

  networking.hostName = "tpm-test-vm";
  networking.hostId = "12345678";

  keystone.disko = {
    enable = true;
    device = "/dev/vda";
    swapSize = "2G";
  };

  keystone.secureBoot.enable = true;
  keystone.tpmEnrollment.enable = true;

  system.stateVersion = "25.05";
}
```

**Deploy**:
```bash
$ nixos-anywhere --flake .#tpm-test-vm root@192.168.100.99
```

---

## Test Suite

### Test 1: User Story 1 - First-Boot Banner Appears

**Objective**: Verify enrollment warning banner displays on first login

**Prerequisites**:
- Fresh installation deployed
- System rebooted successfully
- TPM not yet enrolled

**Steps**:
1. SSH into test VM:
   ```bash
   $ ssh root@192.168.100.99
   ```

2. Observe login output

**Expected Results**:
- ✓ Warning banner appears with "TPM ENROLLMENT NOT CONFIGURED"
- ✓ Banner explains security risk of default password
- ✓ Banner provides enrollment commands
- ✓ Banner includes documentation reference

**Validation**:
```bash
# Check marker file does NOT exist
$ test ! -f /var/lib/keystone/tpm-enrollment-complete && echo "PASS: No marker file" || echo "FAIL: Marker exists"

# Check no TPM keyslot exists
$ sudo systemd-cryptenroll /dev/zvol/rpool/credstore | grep -q "tpm2" && echo "FAIL: TPM enrolled" || echo "PASS: No TPM keyslot"
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 2: User Story 1 - Banner Suppressed After Enrollment

**Objective**: Verify banner disappears after manual TPM enrollment

**Prerequisites**:
- Test 1 completed
- Still logged into test VM

**Steps**:
1. Manually enroll TPM (to test self-healing):
   ```bash
   $ echo -n "keystone" | sudo systemd-cryptenroll \
       /dev/zvol/rpool/credstore \
       --tpm2-device=auto \
       --tpm2-pcrs=1,7 \
       --wipe-slot=empty
   ```

2. Logout:
   ```bash
   $ logout
   ```

3. Login again:
   ```bash
   $ ssh root@192.168.100.99
   ```

**Expected Results**:
- ✓ No warning banner appears
- ✓ Self-healing creates marker file automatically

**Validation**:
```bash
# Check marker file was auto-created
$ cat /var/lib/keystone/tpm-enrollment-complete
# Should show: "Method: auto-detected"

# Verify TPM keyslot exists
$ sudo systemd-cryptenroll /dev/zvol/rpool/credstore | grep tpm2
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 3: User Story 2 - Recovery Key Enrollment

**Objective**: Verify complete recovery key enrollment workflow

**Prerequisites**:
- Fresh VM deployment (or reset from Test 2)
- Banner appears on login

**Steps**:
1. Run recovery key enrollment:
   ```bash
   $ sudo keystone-enroll-recovery
   ```

2. Observe prerequisite checks:
   - Secure Boot enabled ✓
   - TPM2 device detected ✓
   - Credstore volume found ✓

3. Save displayed recovery key (write it down for testing)

4. Press ENTER to continue

5. Observe enrollment completion:
   - Recovery key added ✓
   - TPM enrolled ✓
   - Default password removed ✓

**Expected Results**:
- ✓ Recovery key displayed in formatted box
- ✓ Security warnings shown
- ✓ TPM enrollment succeeds
- ✓ Default password removed
- ✓ Marker file created
- ✓ Success message displayed

**Validation**:
```bash
# Check keyslot configuration
$ sudo systemd-cryptenroll /dev/zvol/rpool/credstore
# Expected output:
# SLOT TYPE
#    1 recovery
#    2 tpm2
# (slot 0 should be gone)

# Check marker file
$ cat /var/lib/keystone/tpm-enrollment-complete | grep "recovery-key"

# Verify banner suppressed
$ logout && ssh root@192.168.100.99
# No banner should appear
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 4: User Story 2 - Automatic Unlock After Enrollment

**Objective**: Verify TPM automatic unlock works after recovery key enrollment

**Prerequisites**:
- Test 3 completed successfully

**Steps**:
1. Reboot the VM:
   ```bash
   $ sudo reboot
   ```

2. Watch boot process (via serial console or SPICE)

3. Observe disk unlock behavior

**Expected Results**:
- ✓ No password prompt appears during boot
- ✓ System unlocks credstore automatically via TPM
- ✓ System boots to login prompt
- ✓ Boot time under 30 seconds (per SC-003)

**Validation**:
```bash
# After system boots, check boot logs
$ sudo journalctl -b | grep credstore

# Should NOT contain "Please enter passphrase"
# Should contain successful TPM unlock messages

# Verify TPM was used for unlock
$ sudo journalctl -b | grep -i "tpm.*credstore"
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 5: User Story 2 - Recovery Key Works When TPM Fails

**Objective**: Verify recovery key unlocks disk when TPM unavailable

**Prerequisites**:
- Test 4 completed (TPM enrolled)
- Recovery key saved from Test 3

**Steps**:
1. Shutdown VM:
   ```bash
   $ sudo shutdown -h now
   ```

2. Disable TPM in VM configuration:
   ```bash
   $ virsh edit tpm-test-vm
   # Comment out or remove <tpm> section
   ```

3. Start VM:
   ```bash
   $ virsh start tpm-test-vm
   ```

4. Watch boot process - password prompt should appear

5. Enter the recovery key saved from Test 3

**Expected Results**:
- ✓ Boot prompts for password (TPM unlock failed as expected)
- ✓ Recovery key successfully unlocks disk
- ✓ System boots normally
- ✓ Login prompt appears

**Validation**:
```bash
# Check boot logs show TPM unlock failed
$ sudo journalctl -b | grep -i "failed.*tpm\|could not.*tpm"

# System should still be functional
$ uptime
```

**Cleanup**:
```bash
# Re-enable TPM in VM config for subsequent tests
$ virsh edit tpm-test-vm
# Restore <tpm> section
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 6: User Story 3 - Custom Password Enrollment

**Objective**: Verify custom password enrollment workflow with validation

**Prerequisites**:
- Fresh VM deployment
- Banner appears on login

**Steps**:
1. Run custom password enrollment:
   ```bash
   $ sudo keystone-enroll-password
   ```

2. Test password validation:
   - Enter password < 12 chars → should reject with error
   - Enter "keystone" → should reject (prohibited)
   - Enter mismatched passwords → should reject
   - Enter valid 16-char password → should accept

3. Confirm password

4. Observe enrollment completion

**Expected Results**:
- ✓ Password validation rejects invalid inputs with clear errors
- ✓ Password validation accepts valid passwords (12-64 chars)
- ✓ Custom password added to LUKS keyslot
- ✓ TPM enrollment succeeds
- ✓ Default password removed
- ✓ Success message displayed

**Validation**:
```bash
# Check keyslot configuration
$ sudo systemd-cryptenroll /dev/zvol/rpool/credstore
# Expected:
# SLOT TYPE
#    1 password
#    2 tpm2

# Check marker file
$ cat /var/lib/keystone/tpm-enrollment-complete | grep "custom-password"

# Test custom password works (before rebooting)
$ echo "your-password" | sudo cryptsetup open --test-passphrase /dev/zvol/rpool/credstore
# Exit code 0 = success
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 7: User Story 3 - Custom Password Recovery

**Objective**: Verify custom password unlocks disk when TPM fails

**Prerequisites**:
- Test 6 completed (custom password enrolled)
- Password saved

**Steps**:
1. Reboot VM to test automatic unlock:
   ```bash
   $ sudo reboot
   ```

2. Verify automatic unlock works (no password prompt)

3. Remove TPM keyslot to simulate TPM failure:
   ```bash
   $ sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/zvol/rpool/credstore
   ```

4. Reboot:
   ```bash
   $ sudo reboot
   ```

5. Enter custom password at boot prompt

**Expected Results**:
- ✓ First reboot: automatic unlock works
- ✓ After TPM removal: password prompt appears
- ✓ Custom password successfully unlocks disk
- ✓ System boots normally

**Status**: [ ] PASS / [ ] FAIL

---

### Test 8: User Story 4 - Standalone TPM Enrollment

**Objective**: Verify advanced standalone TPM enrollment script

**Prerequisites**:
- Fresh VM deployment
- Manually add recovery key without using keystone scripts:
  ```bash
  $ echo -n "keystone" | sudo systemd-cryptenroll --recovery-key /dev/zvol/rpool/credstore
  ```

**Steps**:
1. Run standalone TPM enrollment:
   ```bash
   $ sudo keystone-enroll-tpm
   ```

2. Confirm when prompted (default password warning)

3. Observe TPM enrollment

**Expected Results**:
- ✓ Warning about default password still active
- ✓ User can choose to continue or cancel
- ✓ TPM enrollment succeeds
- ✓ Verification checks pass
- ✓ Marker file created

**Validation**:
```bash
# Check both recovery key and TPM exist
$ sudo systemd-cryptenroll /dev/zvol/rpool/credstore
# Expected:
# SLOT TYPE
#    0 password  # Default still exists (warning given)
#    1 recovery
#    2 tpm2
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 9: PCR Configuration - Default [1,7]

**Objective**: Verify default PCR configuration works correctly

**Prerequisites**:
- Fresh VM with default configuration (tpmPCRs = [1 7])

**Steps**:
1. Enroll with default PCRs:
   ```bash
   $ sudo keystone-enroll-recovery
   ```

2. Reboot and verify automatic unlock

3. Check enrolled PCRs:
   ```bash
   $ sudo cryptsetup luksDump /dev/zvol/rpool/credstore | grep tpm2-hash-pcrs
   ```

**Expected Results**:
- ✓ Enrollment uses PCRs 1,7
- ✓ LUKS header shows `tpm2-hash-pcrs: 1+7`
- ✓ Automatic unlock works

**Status**: [ ] PASS / [ ] FAIL

---

### Test 10: PCR Configuration - Custom [7]

**Objective**: Verify custom PCR configuration (Secure Boot only)

**Prerequisites**:
- VM configuration with custom PCR:
  ```nix
  keystone.tpmEnrollment.tpmPCRs = [ 7 ];
  ```
- Rebuild and redeploy

**Steps**:
1. Enroll with custom PCRs:
   ```bash
   $ sudo keystone-enroll-recovery
   ```

2. Verify enrolled PCRs:
   ```bash
   $ sudo cryptsetup luksDump /dev/zvol/rpool/credstore | grep tpm2-hash-pcrs
   ```

**Expected Results**:
- ✓ Enrollment uses PCR 7 only
- ✓ LUKS header shows `tpm2-hash-pcrs: 7`
- ✓ Automatic unlock works

**Status**: [ ] PASS / [ ] FAIL

---

### Test 11: PCR Configuration - Multiple Custom [0,1,7]

**Objective**: Verify multiple custom PCRs work correctly

**Prerequisites**:
- VM configuration with:
  ```nix
  keystone.tpmEnrollment.tpmPCRs = [ 0 1 7 ];
  ```

**Steps**:
1. Enroll with multiple PCRs
2. Verify configuration
3. Test automatic unlock

**Expected Results**:
- ✓ LUKS header shows `tpm2-hash-pcrs: 0+1+7`
- ✓ Automatic unlock works

**Status**: [ ] PASS / [ ] FAIL

---

### Test 12: Error Handling - No Secure Boot

**Objective**: Verify graceful failure when Secure Boot not enabled

**Prerequisites**:
- VM in Setup Mode (Secure Boot not enrolled)

**Steps**:
1. Attempt enrollment:
   ```bash
   $ sudo keystone-enroll-recovery
   ```

**Expected Results**:
- ✓ Error message: "Secure Boot is not enabled"
- ✓ Clear explanation of User Mode requirement
- ✓ Suggests checking sbctl status
- ✓ Exit code 1
- ✓ Default password remains active

**Status**: [ ] PASS / [ ] FAIL

---

### Test 13: Error Handling - No TPM Device

**Objective**: Verify graceful failure when TPM unavailable

**Prerequisites**:
- VM without TPM emulation

**Steps**:
1. Create VM without TPM:
   ```bash
   # Manually create VM or edit existing to remove TPM
   ```

2. Deploy and attempt enrollment:
   ```bash
   $ sudo keystone-enroll-recovery
   ```

**Expected Results**:
- ✓ Error message: "No TPM2 device found"
- ✓ Helpful guidance for VMs and bare metal
- ✓ Exit code 2
- ✓ System continues working (password-based unlock)

**Status**: [ ] PASS / [ ] FAIL

---

### Test 14: Password Validation - Too Short

**Objective**: Verify password minimum length enforcement

**Steps**:
1. Run password enrollment:
   ```bash
   $ sudo keystone-enroll-password
   ```

2. Enter password with 8 characters

**Expected Results**:
- ✓ Error message with character count
- ✓ Examples of valid passwords shown
- ✓ Prompt loops back for retry
- ✓ No LUKS changes made

**Status**: [ ] PASS / [ ] FAIL

---

### Test 15: Password Validation - Prohibited "keystone"

**Objective**: Verify default password cannot be re-used

**Steps**:
1. Run password enrollment
2. Enter "keystone" as password

**Expected Results**:
- ✓ Error: "This password is not allowed"
- ✓ Explanation that it's publicly known
- ✓ Prompt for different password

**Status**: [ ] PASS / [ ] FAIL

---

### Test 16: Password Validation - Mismatch

**Objective**: Verify password confirmation works

**Steps**:
1. Run password enrollment
2. Enter valid password
3. Enter different password for confirmation

**Expected Results**:
- ✓ Error: "Passwords do not match"
- ✓ Prompt loops back to start
- ✓ No LUKS changes made

**Status**: [ ] PASS / [ ] FAIL

---

### Test 17: Password Validation - Valid Password

**Objective**: Verify valid passwords accepted

**Steps**:
1. Run password enrollment
2. Enter password "MyTestPassword2024" (18 chars)
3. Confirm correctly

**Expected Results**:
- ✓ Validation passes
- ✓ Password added to LUKS
- ✓ TPM enrollment succeeds
- ✓ System ready for automatic unlock

**Status**: [ ] PASS / [ ] FAIL

---

### Test 18: PCR Mismatch Recovery

**Objective**: Verify recovery when PCR values change

**Prerequisites**:
- VM with TPM enrolled
- Recovery key saved

**Steps**:
1. Verify automatic unlock works:
   ```bash
   $ sudo reboot
   # No password prompt
   ```

2. Change Secure Boot state to trigger PCR 7 change:
   ```bash
   # This is simulated - in real scenario would disable/re-enable Secure Boot
   $ sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/zvol/rpool/credstore
   ```

3. Reboot:
   ```bash
   $ sudo reboot
   ```

4. Enter recovery key at password prompt

5. Re-enroll TPM:
   ```bash
   $ sudo keystone-enroll-tpm
   ```

6. Reboot again to verify automatic unlock restored

**Expected Results**:
- ✓ After TPM removed: password prompt appears
- ✓ Recovery key unlocks successfully
- ✓ Re-enrollment succeeds
- ✓ Automatic unlock restored after re-enrollment

**Status**: [ ] PASS / [ ] FAIL

---

### Test 19: Self-Healing Marker File

**Objective**: Verify marker file self-healing logic

**Prerequisites**:
- VM with TPM enrolled

**Steps**:
1. Manually delete marker file:
   ```bash
   $ sudo rm /var/lib/keystone/tpm-enrollment-complete
   ```

2. Logout and login again:
   ```bash
   $ logout
   $ ssh root@192.168.100.99
   ```

**Expected Results**:
- ✓ No banner appears (TPM still enrolled)
- ✓ Marker file automatically recreated
- ✓ Marker contains "auto-detected" method

**Validation**:
```bash
$ cat /var/lib/keystone/tpm-enrollment-complete
# Should exist and show auto-detection
```

**Status**: [ ] PASS / [ ] FAIL

---

### Test 20: Multiple Credentials (Recovery + Password)

**Objective**: Verify system supports multiple recovery credentials

**Prerequisites**:
- Fresh VM

**Steps**:
1. Enroll recovery key:
   ```bash
   $ sudo keystone-enroll-recovery
   ```

2. Add custom password as additional credential:
   ```bash
   $ echo -n "<recovery-key>" | sudo systemd-cryptenroll --password /dev/zvol/rpool/credstore
   # Enter new password when prompted
   ```

3. Test both credentials work:
   ```bash
   $ sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/zvol/rpool/credstore
   $ sudo reboot
   # Test recovery key at prompt

   $ sudo reboot
   # Test custom password at prompt
   ```

**Expected Results**:
- ✓ Both recovery key AND custom password exist
- ✓ Both credentials unlock disk successfully
- ✓ LUKS shows 3 keyslots (recovery, password, tpm2)

**Status**: [ ] PASS / [ ] FAIL

---

### Test 21: Build Validation

**Objective**: Verify module builds successfully

**Steps**:
```bash
# Test configuration build
$ nix build .#nixosConfigurations.test-server.config.system.build.toplevel

# Check for build errors or warnings
```

**Expected Results**:
- ✓ Build succeeds without errors
- ✓ No Nix evaluation warnings
- ✓ Module assertions properly validated at build time

**Status**: [ ] PASS / [ ] FAIL

---

### Test 22: Module Assertions

**Objective**: Verify module assertions catch configuration errors

**Test Case A - Missing Secure Boot**:
```nix
keystone.secureBoot.enable = false;
keystone.tpmEnrollment.enable = true;
```

**Expected**: Build fails with assertion error about Secure Boot

**Test Case B - Missing Disko**:
```nix
keystone.disko.enable = false;
keystone.tpmEnrollment.enable = true;
```

**Expected**: Build fails with assertion error about disko

**Test Case C - Empty PCR List**:
```nix
keystone.tpmEnrollment.tpmPCRs = [ ];
```

**Expected**: Build fails with assertion error about empty PCR list

**Test Case D - Invalid PCR Number**:
```nix
keystone.tpmEnrollment.tpmPCRs = [ 99 ];
```

**Expected**: Build fails with assertion error about PCR range 0-23

**Status**: [ ] PASS / [ ] FAIL

---

## Test Execution Summary

| Test | User Story | Status | Notes |
|------|-----------|--------|-------|
| 1 | US1 | [ ] | Banner appears on first login |
| 2 | US1 | [ ] | Banner suppressed after enrollment |
| 3 | US2 | [ ] | Recovery key enrollment workflow |
| 4 | US2 | [ ] | Automatic unlock works |
| 5 | US2 | [ ] | Recovery key unlocks when TPM fails |
| 6 | US3 | [ ] | Custom password enrollment workflow |
| 7 | US3 | [ ] | Password validation (too short) |
| 8 | US3 | [ ] | Password validation (prohibited) |
| 9 | US3 | [ ] | Password validation (mismatch) |
| 10 | US3 | [ ] | Password validation (valid) |
| 11 | US4 | [ ] | Standalone TPM enrollment |
| 12 | US4 | [ ] | PCR mismatch recovery |
| 13 | Edge | [ ] | Error: No Secure Boot |
| 14 | Edge | [ ] | Error: No TPM device |
| 15 | Edge | [ ] | Self-healing marker file |
| 16 | Edge | [ ] | Multiple credentials |
| 17 | Build | [ ] | Build validation |
| 18 | Build | [ ] | Module assertions |
| 19 | Config | [ ] | Default PCR config [1,7] |
| 20 | Config | [ ] | Custom PCR config [7] |
| 21 | Config | [ ] | Custom PCR config [0,1,7] |

## Success Criteria Validation

Map test results to spec success criteria:

| Criteria | Tests | Status |
|----------|-------|--------|
| SC-001: Notification within 10s | Test 1 | [ ] |
| SC-002: Enrollment under 5 min | Tests 3, 6 | [ ] |
| SC-003: Boot unlock under 30s | Test 4 | [ ] |
| SC-004: Recovery 100% reliable | Tests 5, 7 | [ ] |
| SC-005: Graceful error messages | Tests 13, 14 | [ ] |
| SC-006: Default password removed | Tests 3, 6 | [ ] |
| SC-007: Clear documentation | Manual review | [ ] |

---

## Test Environment Cleanup

After completing all tests:

```bash
# Stop and delete test VM
$ ./bin/virtual-machine --reset tpm-test-vm

# Or keep for future testing
$ virsh shutdown tpm-test-vm
```

---

**Test Plan Version**: 1.0
**Date**: 2025-11-03
**Status**: Ready for Execution
