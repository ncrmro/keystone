# Quickstart: Secure Boot Custom Key Enrollment

**Feature**: Secure Boot Custom Key Enrollment
**Audience**: Keystone developers and contributors
**Time**: ~10 minutes for full workflow

## Overview

This guide walks you through generating custom Secure Boot keys, enrolling them in a test VM, and verifying successful enrollment. By the end, you'll have a VM booting with Secure Boot enabled using your own Platform Key (PK), Key Exchange Key (KEK), and signature database (db).

**What you'll learn**:
- How to generate custom Secure Boot keys using sbctl
- How to enroll keys in UEFI firmware (Setup Mode → User Mode)
- How to verify Secure Boot status with bootctl and EFI variables
- How automated testing validates Secure Boot enrollment

---

## Prerequisites

Before you begin:

- **NixOS system** with libvirtd enabled
- **bin/virtual-machine** script tested (VM creation works)
- **bin/build-iso** produces bootable installer
- **SSH access** to VMs via 192.168.100.99
- **Root access** (sudo) for key generation and enrollment

**Verify prerequisites**:
```bash
# Check libvirtd is running
systemctl status libvirtd

# Verify VM script works
./bin/virtual-machine --help

# Confirm sbctl available
nix-shell -p sbctl --run "sbctl --version"
```

---

## Step-by-Step Workflow

### Step 1: Create Test VM in Setup Mode

The VM must boot in Setup Mode (no pre-enrolled keys) for custom key enrollment.

```bash
# Create and start VM with Keystone installer ISO
./bin/virtual-machine --name keystone-test-vm --start

# Wait for VM to boot (~30 seconds)
# The VM automatically boots in Setup Mode (verified in spec 003)
```

**Verify Setup Mode**:
```bash
# Connect via SSH (wait for installer to boot)
ssh root@192.168.100.99

# Inside VM: Check Secure Boot status
bootctl status

# Expected output:
#   Secure Boot: disabled (setup)
#   Setup Mode: setup
```

**What this means**:
- `disabled (setup)`: Firmware has Secure Boot capability but no keys enrolled
- `Setup Mode: setup`: Platform Key (PK) is NOT enrolled, ready for custom key enrollment

---

### Step 2: Generate Custom Secure Boot Keys

Generate your own PK, KEK, and db keys using sbctl.

**Inside the VM**:
```bash
# Generate keys (takes ~3-5 seconds)
sbctl create-keys

# Expected output:
# Created Owner UUID 8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd
# Creating secure boot keys...
# ✔ Secure boot keys created!
```

**Verify keys were created**:
```bash
# Check key files exist
ls -la /var/lib/sbctl/keys/

# Expected structure:
# /var/lib/sbctl/keys/
# ├── PK/   (Platform Key)
# ├── KEK/  (Key Exchange Key)
# └── db/   (Signature Database)

# Verify permissions
ls -l /var/lib/sbctl/keys/db/db.key
# Should show: -rw------- 1 root root (600 permissions, root-only)
```

**What was created**:
- **12 key files** (4 formats × 3 key types):
  - `.key` - Private key (RSA4096, root-only 600 permissions)
  - `.pem` - Public certificate (world-readable 644)
  - `.auth` - Authenticated update file (for UEFI enrollment)
  - `.esl` - EFI Signature List (binary format)
- **Owner GUID** in `/var/lib/sbctl/GUID`

---

### Step 3: Enroll Keys in Firmware

Enroll your custom keys to transition from Setup Mode to User Mode.

**⚠️ IMPORTANT**: For VMs, use custom-only keys (no Microsoft certificates). For physical hardware, include `--microsoft` flag.

**Inside the VM**:
```bash
# Enroll custom keys only (safe for VMs)
sbctl enroll-keys --yes-this-might-brick-my-machine

# Expected output:
# Enrolling keys to EFI variables...
# ✔ Enrolled keys to the EFI variables!
```

**Why the scary flag name?**
- On physical hardware, enrolling custom-only keys can brick the system if hardware option ROMs require Microsoft certificates
- For VMs with emulated hardware, this is SAFE (no physical firmware to brick)
- The flag forces you to acknowledge the risk

**Alternative (physical hardware)**:
```bash
# Include Microsoft OEM certificates (for GPUs, network cards, etc.)
sbctl enroll-keys --microsoft
```

**What happened**:
- Firmware variables updated: `PK`, `KEK`, `db` now contain your keys
- `SetupMode` variable changed from 1 → 0 (Setup Mode → User Mode)
- `SecureBoot` variable changed from 0 → 1 (enforcing signatures)

---

### Step 4: Verify Secure Boot Enabled

Confirm the enrollment succeeded and Secure Boot is now active.

**Inside the VM**:
```bash
# Check Secure Boot status
bootctl status

# Expected output:
#   Secure Boot: enabled (user)
#   Setup Mode: user
#   Firmware: UEFI 2.70 (EDK II 1.00)
```

**Verify with sbctl**:
```bash
# Alternative verification using sbctl
sbctl status

# Expected output:
# Installed:    ✓ sbctl is installed
# Owner GUID:   8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd
# Setup Mode:   ✗ Disabled  (was: ✓ Enabled)
# Secure Boot:  ✓ Enabled   (was: ✗ Disabled)
```

**Verify with EFI variables (advanced)**:
```bash
# Check SetupMode variable directly
od --address-radix=n --format=u1 \
  /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c

# Expected: Last byte is 0 (User Mode)
# Output: 7   0   0   0   0
#                         ↑ 0 = User Mode

# Check SecureBoot variable
od --address-radix=n --format=u1 \
  /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c

# Expected: Last byte is 1 (Enforcing)
# Output: 7   0   0   0   1
#                         ↑ 1 = Enforcing
```

**Success indicators**:
- ✅ `Secure Boot: enabled (user)` in bootctl
- ✅ `Setup Mode: ✗ Disabled` in sbctl status
- ✅ `Secure Boot: ✓ Enabled` in sbctl status
- ✅ SetupMode variable == 0
- ✅ SecureBoot variable == 1

---

### Step 5: Test Reboot (Optional)

Verify Secure Boot persists across reboots.

**Exit SSH and reboot VM**:
```bash
# Inside VM
reboot

# Wait for reboot (~30 seconds)
# Reconnect
ssh root@192.168.100.99

# Verify Secure Boot still enabled
bootctl status
# Should still show: "Secure Boot: enabled (user)"
```

**What this confirms**:
- Keys persist in firmware NVRAM (non-volatile)
- Secure Boot enforcement active at boot time
- Firmware rejects unsigned code

---

## Automated Testing Integration

The bin/test-deployment script automates this entire workflow.

**Run full automated test**:
```bash
# Hard reset + rebuild ISO + full deployment test
./bin/test-deployment --rebuild-iso --hard-reset

# The script will:
# 1. Reset VM to clean state
# 2. Rebuild Keystone ISO
# 3. Start VM from ISO
# 4. Wait for SSH
# 5. Verify Setup Mode
# 6. Deploy NixOS with nixos-anywhere
# 7. Generate Secure Boot keys
# 8. Enroll keys
# 9. Verify User Mode
# 10. Run verification tests
```

**Test output** (relevant section):
```
[7/9] Verifying Secure Boot setup mode
ℹ Verifying Secure Boot setup mode...
✓ Secure Boot setup mode confirmed: Secure Boot: disabled (setup)

[8/9] Deploying with nixos-anywhere
ℹ Starting nixos-anywhere deployment...
✓ Deployment phase completed!

[9/9] Verifying Secure Boot enabled
ℹ Verifying Secure Boot status...
✓ Secure Boot enabled with custom keys
  Mode: user
  Enforcing: true
  Keys: PK=true, KEK=true, db=true

✓ All tests passed!
```

---

## Troubleshooting

### Problem: "Firmware not in Setup Mode"

**Symptoms**:
```
Error: Firmware not in Setup Mode. SetupMode variable is 0 (already enrolled).
```

**Cause**: VM already has keys enrolled (previous test run).

**Solution**: Reset VM to Setup Mode:
```bash
# Shut down VM first
virsh shutdown keystone-test-vm

# Reset NVRAM to Setup Mode
./bin/virtual-machine --reset-setup-mode keystone-test-vm

# Start VM again
virsh start keystone-test-vm

# Verify Setup Mode
ssh root@192.168.100.99 "bootctl status"
```

---

### Problem: Keys already exist

**Symptoms**:
```
Error: Keys already exist at /var/lib/sbctl/keys/. Use --force to overwrite.
```

**Cause**: Previous key generation left files in place.

**Solution**: Force regeneration or use existing keys:
```bash
# Option 1: Regenerate (fresh keys)
sbctl create-keys --force  # (fictional flag, adjust based on sbctl version)
# OR
rm -rf /var/lib/sbctl/keys/ && sbctl create-keys

# Option 2: Use existing keys
# Just skip to enrollment step
sbctl enroll-keys --yes-this-might-brick-my-machine
```

---

### Problem: bootctl not available

**Symptoms**:
```
bash: bootctl: command not found
```

**Cause**: Minimal installer environment may not include systemd-boot tools.

**Solution**: Use direct EFI variable reading:
```bash
# Check SetupMode manually
cat /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c | od -An -t u1
# Last byte: 1 = setup, 0 = user

# Check SecureBoot manually
cat /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | od -An -t u1
# Last byte: 0 = disabled, 1 = enabled
```

---

### Problem: Enrollment fails silently

**Symptoms**:
- `sbctl enroll-keys` reports success
- But `bootctl status` still shows `disabled (setup)`

**Diagnosis**:
```bash
# Check if PK was actually enrolled
ls -la /sys/firmware/efi/efivars/PK-*

# If file is very small (< 100 bytes), PK not enrolled
stat /sys/firmware/efi/efivars/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c
```

**Possible causes**:
1. Firmware incompatibility (rare with OVMF)
2. Key format issue
3. Insufficient permissions (not running as root)

**Solution**: Try efitools as fallback (not recommended, complex):
```bash
# Load keys via KeyTool.efi (requires UEFI shell access)
# See efitools documentation
```

---

## Next Steps

### For Production Deployment

1. **Physical Hardware**: Use `--microsoft` flag when enrolling keys
2. **Key Backup**: Store keys securely (they're unique per system)
3. **lanzaboote Integration**: Configure lanzaboote to sign boot files
4. **Monitoring**: Add Secure Boot status to system health checks

### For Development

1. **Automated Testing**: Run `./bin/test-deployment` after changes
2. **Script Development**: Wrap sbctl commands in scripts/ directory
3. **Error Handling**: Add robust error checking and JSON output
4. **Documentation**: Update CLAUDE.md with Secure Boot workflow

---

## Reference Commands

**Quick Command Reference**:

```bash
# VM Management
./bin/virtual-machine --name <vm> --start          # Create VM
./bin/virtual-machine --reset <vm>                 # Delete VM
./bin/virtual-machine --reset-setup-mode <vm>      # Reset to Setup Mode
virsh console <vm>                                 # Serial console
ssh root@192.168.100.99                            # SSH to VM

# Key Management
sbctl create-keys                                  # Generate keys
sbctl enroll-keys --yes-this-might-brick-my-machine  # Enroll (VMs)
sbctl enroll-keys --microsoft                      # Enroll (physical HW)
sbctl status                                       # Check sbctl status

# Verification
bootctl status                                     # Primary verification
sbctl verify                                       # Check signed files
od -An -t u1 /sys/firmware/efi/efivars/SetupMode-* # Manual SetupMode check

# Testing
./bin/test-deployment                              # Run full test
./bin/test-deployment --rebuild-iso                # Rebuild ISO first
./bin/test-deployment --hard-reset                 # Clean slate test
```

---

## Architecture Overview

**Workflow Diagram**:
```
┌─────────────────┐
│  VM in Setup    │
│  Mode (OVMF)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Generate Keys   │ → /var/lib/sbctl/keys/{PK,KEK,db}
│  (sbctl)        │   (12 files: .key, .pem, .auth, .esl)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Enroll Keys    │ → UEFI NVRAM variables: PK, KEK, db
│  (sbctl)        │   SetupMode: 1 → 0
│                 │   SecureBoot: 0 → 1
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Verify Status   │ → bootctl status
│  (bootctl)      │   "Secure Boot: enabled (user)"
└─────────────────┘
```

**Security Model**:
- **PK (Platform Key)**: Root of trust, owner's key
- **KEK (Key Exchange Key)**: Can update db and dbx
- **db (Signature Database)**: Trusted signers for boot code
- **Transition**: PK enrollment locks firmware (Setup → User Mode)
- **Enforcement**: Only code signed with db keys can execute

---

## Learn More

- **lanzaboote Quick Start**: https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md
- **sbctl GitHub**: https://github.com/Foxboron/sbctl
- **UEFI Spec**: https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html
- **Keystone Constitution**: `.specify/memory/constitution.md`
- **Spec 003**: `specs/003-secureboot-setup-mode/` (OVMF Setup Mode configuration)

---

**Quickstart Status**: ✅ Complete - Ready for development
