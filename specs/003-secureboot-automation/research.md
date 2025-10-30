# Research Findings: Secure Boot Automation with Lanzaboote

**Date**: 2025-10-29
**Feature**: 003-secureboot-automation
**Purpose**: Resolve technical unknowns for implementing automated Secure Boot enrollment in test-vm script

## Research Questions Addressed

1. Lanzaboote enrollment commands/API
2. UEFI variable access methods in NixOS environment
3. VM firmware requirements (OVMF version, Secure Boot variable support)

---

## 1. Lanzaboote Enrollment Commands/API

### Decision
Use **sbctl** CLI commands with lanzaboote's `enrollKeys` option for testing

### Rationale
- sbctl is the de facto standard Secure Boot key manager for NixOS (available as `pkgs.sbctl`)
- Lanzaboote provides a NixOS module with direct sbctl integration
- Well-documented workflow with clear state transitions
- Programmatic verification available through multiple sbctl commands

### Key Commands

**Key Generation:**
```bash
sudo sbctl create-keys
```
Creates Secure Boot key pair in `/var/lib/sbctl` with files: `db.key`, `db.pem`, plus PK and KEK

**Key Enrollment:**
```bash
sudo sbctl enroll-keys --microsoft
# For automated testing (bypasses confirmation):
sudo sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine
```

**Status Verification:**
```bash
sbctl status
```

Expected progression:
- Before enrollment: `Setup Mode: ✘ Enabled`, `Secure Boot: ✘ Disabled`
- After enrollment: `Setup Mode: ✔ Disabled`, `Secure Boot: ✘ Disabled`
- After BIOS enable: `Setup Mode: ✔ Disabled`, `Secure Boot: ✔ Enabled`

**Signature Verification:**
```bash
sbctl verify  # Checks if all boot files are properly signed
```

### Lanzaboote NixOS Configuration

**Production Setup:**
```nix
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
```

**Testing Setup (ONLY for automated tests):**
```nix
{
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    enrollKeys = true;  # WARNING: Testing only! Never use in production
  };
}
```

When `enrollKeys = true`, lanzaboote automatically runs:
```bash
cp -r ${pkiBundle}/* /tmp/pki
sbctl enroll-keys --yes-this-might-brick-my-machine
```

### Alternatives Considered
- **Manual UEFI key enrollment via efitools**: Too complex, no NixOS integration
- **systemd-boot native Secure Boot**: Not yet mature in NixOS
- **Custom signing scripts**: Reinventing the wheel

---

## 2. UEFI Variable Access in NixOS

### Decision
Use **bootctl status** for high-level checks, **sysfs** for programmatic verification

### Rationale
- bootctl (systemd component) provides user-friendly, parsed output
- Linux kernel exposes UEFI variables via sysfs at `/sys/firmware/efi/efivars/`
- Both available by default in NixOS with systemd
- No additional dependencies required

### Verification Methods

**High-level status check:**
```bash
bootctl status | grep "Secure Boot:"
# Output: "Secure Boot: enabled (user)" or "Secure Boot: disabled"
```

**Programmatic sysfs check:**
```bash
# Check SecureBoot variable (returns 1 if enabled, 0 if disabled)
cat /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | od -An -t u1 | awk '{print $NF}'

# Check SetupMode variable (returns 0 for User Mode, 1 for Setup Mode)
cat /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c | od -An -t u1 | awk '{print $NF}'
```

**Python verification helper:**
```python
def check_secure_boot_status():
    """Check if Secure Boot is enabled via sysfs"""
    try:
        with open('/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c', 'rb') as f:
            data = f.read()
            # Last byte is the value: 1 = enabled, 0 = disabled
            return data[-1] == 1
    except FileNotFoundError:
        return False

def check_setup_mode():
    """Check if system is in Setup Mode"""
    try:
        with open('/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c', 'rb') as f:
            data = f.read()
            # Last byte: 0 = User Mode (keys enrolled), 1 = Setup Mode
            return data[-1] == 1
    except FileNotFoundError:
        return None
```

### Complete Verification Workflow

```bash
#!/usr/bin/env bash
# Check UEFI mode
if [ ! -d /sys/firmware/efi ]; then
    echo "ERROR: Not booted in UEFI mode"
    exit 1
fi

# Check Setup Mode (should be 0 after enrollment)
setup_mode=$(cat /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c | od -An -t u1 | awk '{print $NF}')
if [ "$setup_mode" = "1" ]; then
    echo "FAIL: System is in Setup Mode (keys not enrolled)"
    exit 1
fi

# Check Secure Boot enabled
secure_boot=$(cat /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | od -An -t u1 | awk '{print $NF}')
if [ "$secure_boot" != "1" ]; then
    echo "FAIL: Secure Boot is not enabled"
    exit 1
fi

# Verify with bootctl
if ! bootctl status | grep -q "Secure Boot: enabled"; then
    echo "FAIL: bootctl does not show Secure Boot enabled"
    exit 1
fi

# Verify with sbctl
if ! sbctl status | grep -q "Secure Boot:.*Enabled"; then
    echo "FAIL: sbctl does not show Secure Boot enabled"
    exit 1
fi

echo "SUCCESS: Secure Boot is properly configured and enabled"
```

### Alternatives Considered
- **efivar command**: More complex than sysfs, unnecessary dependency
- **mokutil**: Only relevant for shim-based Secure Boot (not lanzaboote)
- **UEFI Shell commands**: Too complex for automated testing

---

## 3. VM Firmware Requirements

### Decision
Use **OVMF with `secureBoot = true` override**, standard VARS file initialization

### Rationale
- OVMF (Open Virtual Machine Firmware) provides UEFI implementation for QEMU/KVM
- NixOS provides OVMF packages with Secure Boot support via overrides
- OVMF starts in Setup Mode by default (perfect for testing key enrollment)
- NixOS test framework supports UEFI boot configuration out of the box

### OVMF Configuration

**NixOS VM Configuration:**
```nix
{
  virtualisation = {
    useEFIBoot = true;
    qemu.options = [
      "-drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.override { secureBoot = true; tpmSupport = true; }}/FV/OVMF_CODE.fd"
    ];
  };
}
```

**QEMU Command Line:**
```bash
qemu-system-x86_64 \
  -drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.override { secureBoot = true; }}/FV/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=./vms/server/OVMF_VARS.fd \
  -machine q35 \
  -enable-kvm \
  -hda disk.qcow2
```

### OVMF File Structure

OVMF requires two files:
1. **OVMF_CODE.fd** - Firmware code (read-only, shared)
2. **OVMF_VARS.fd** - Variable storage (read-write, per-VM)

The VARS file stores:
- NVRAM (boot variables)
- Secure Boot keys (PK, KEK, db, dbx)
- Setup Mode state

### VARS File Initialization

OVMF starts with empty VARS by default (Setup Mode enabled):
```bash
# Copy template VARS file
cp ${pkgs.OVMF.override { secureBoot = true; }}/FV/OVMF_VARS.fd ./vms/server/OVMF_VARS.fd
chmod 644 ./vms/server/OVMF_VARS.fd
```

Initial state:
- `SetupMode = 1` (Setup Mode enabled)
- `SecureBoot = 0` (Secure Boot disabled)
- No keys enrolled

### Current VM Configuration Update Needed

The existing `vms/server.conf` uses quickemu, which may need updates:
- Ensure UEFI boot is enabled
- Use OVMF with Secure Boot support
- Preserve VARS file across VM restarts

### Verification After VM Boot

```bash
# Check UEFI mode
ls /sys/firmware/efi  # Should exist

# Check Secure Boot variables
efivar -l | grep -i secure  # Should show SecureBoot, SetupMode variables

# Check sbctl compatibility
sbctl status  # Should show UEFI Secure Boot capability
```

### Alternatives Considered
- **SeaBIOS (Legacy BIOS)**: No UEFI support, can't test Secure Boot
- **Build OVMF from source**: OVMF override is simpler and sufficient
- **Real hardware**: Not automatable for testing

---

## Implementation Recommendations

### For test-deployment Script

1. **Add Secure Boot capability detection:**
   ```python
   def check_secure_boot_capability():
       """Check if VM firmware supports Secure Boot"""
       result = run_command(
           "ssh -p 22220 -o StrictHostKeyChecking=no root@localhost 'test -d /sys/firmware/efi'",
           check=False
       )
       if not result:
           return False

       # Check for Secure Boot variables
       result = run_command(
           "ssh -p 22220 -o StrictHostKeyChecking=no root@localhost 'test -f /sys/firmware/efi/efivars/SecureBoot-*'",
           check=False
       )
       return result
   ```

2. **Add enrollment trigger function:**
   ```python
   def enroll_secure_boot_keys():
       """Trigger Secure Boot key enrollment via sbctl"""
       print_info("Enrolling Secure Boot keys...")

       # Keys already generated during deployment (lanzaboote module)
       # Enrollment happens automatically if enrollKeys = true in config
       # Or manually trigger:
       cmd = """ssh -p 22220 -o StrictHostKeyChecking=no root@localhost '
           sbctl status
           sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine
       '"""

       return run_command(cmd, timeout=30)
   ```

3. **Add verification function:**
   ```python
   def verify_secure_boot():
       """Verify Secure Boot is enabled and functional"""
       checks = [
           ("UEFI mode", "test -d /sys/firmware/efi"),
           ("Setup Mode disabled", "[ $(cat /sys/firmware/efi/efivars/SetupMode-* | od -An -t u1 | awk '{print $NF}') = '0' ]"),
           ("Secure Boot enabled", "[ $(cat /sys/firmware/efi/efivars/SecureBoot-* | od -An -t u1 | awk '{print $NF}') = '1' ]"),
           ("bootctl confirms", "bootctl status | grep -q 'Secure Boot: enabled'"),
           ("sbctl confirms", "sbctl status | grep -q 'Secure Boot:.*Enabled'"),
       ]

       for check_name, check_cmd in checks:
           full_cmd = f"ssh -p 22220 -o StrictHostKeyChecking=no root@localhost '{check_cmd}'"
           if run_command(full_cmd, check=False):
               print_success(f"{check_name}")
           else:
               print_error(f"{check_name}")
               return False

       return True
   ```

### For NixOS Configuration

Update `examples/test-server.nix` to include lanzaboote:

```nix
{
  # Disable systemd-boot (lanzaboote replaces it)
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # Enable lanzaboote for Secure Boot
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    # Note: enrollKeys = true only for automated testing
    # Production should use manual enrollment
  };
}
```

### For VM Configuration

Ensure `vms/server.conf` uses UEFI firmware:
- Update to use OVMF with Secure Boot support
- Create/manage OVMF_VARS.fd file
- Document UEFI requirements in comments

---

## References

- [Lanzaboote GitHub](https://github.com/nix-community/lanzaboote)
- [sbctl GitHub](https://github.com/Foxboron/sbctl)
- [NixOS Secure Boot Wiki](https://nixos.wiki/wiki/Secure_Boot)
- [UEFI Spec 2.10 - Secure Boot](https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
- [NixOS Secure Boot Tutorial by jnsgr.uk](https://jnsgr.uk/2024/04/nixos-secure-boot-tpm-fde/)

## Resolved Clarifications

All NEEDS CLARIFICATION items from Technical Context have been resolved:

1. ✅ **Lanzaboote enrollment commands/API**: Use sbctl CLI with `enroll-keys` command
2. ✅ **UEFI variable access methods**: Use sysfs (`/sys/firmware/efi/efivars/`) and bootctl
3. ✅ **VM firmware requirements**: OVMF with `secureBoot = true` override, VARS file per-VM
