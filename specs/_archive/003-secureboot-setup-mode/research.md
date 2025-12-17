# Research: Secure Boot Setup Mode for VM Testing

**Date**: 2025-10-31
**Feature**: 003-secureboot-setup-mode
**Target**: bin/virtual-machine Python script enhancement

## Executive Summary

This research documents the technical requirements for configuring VMs to boot in UEFI Secure Boot setup mode using libvirt and OVMF firmware on NixOS. Setup mode allows unsigned operating systems to run while enabling developers to enroll custom Secure Boot keys - essential for testing Keystone's lanzaboote integration.

**Key Finding**: NixOS provides edk2-i386-vars.fd and edk2-x86_64-secure-code.fd firmware files through QEMU that are already in setup mode (no pre-enrolled keys). The bin/virtual-machine script currently copies these correctly but doesn't explicitly configure libvirt for setup mode using modern XML features.

## 1. OVMF Secure Boot Modes

### Decision

Use UEFI Secure Boot setup mode, which is characterized by:
- **SetupMode=1** UEFI variable indicating no Platform Key (PK) is enrolled
- **SecureBoot=0** indicating signature verification is not enforced
- Allows unsigned code to execute while firmware accepts key enrollment
- Transitions to User Mode when a Platform Key is enrolled

### Technical Details

#### Four UEFI Secure Boot Modes

**Setup Mode (Target Mode)**
- **Condition**: Platform Key (PK) is not enrolled (SetupMode=1)
- **Behavior**: Firmware allows unsigned operating systems to boot; all key variables (PK, KEK, db, dbx) can be modified without cryptographic signatures
- **Use Case**: Initial system configuration, custom key enrollment, recovery
- **bootctl output**: "Secure Boot: disabled (setup)"

**User Mode**
- **Condition**: Platform Key is enrolled, not in Deployed Mode (SetupMode=0, DeployedMode=0)
- **Behavior**: Secure Boot can be enabled; signature verification enforces trusted boot chain
- **Transition**: Entered when PK is set from Setup Mode
- **bootctl output**: "Secure Boot: enabled (user)" when active

**Deployed Mode**
- **Condition**: PK installed, DeployedMode=1 (read-only)
- **Behavior**: Most secure mode; programmatic updates to policy objects require signature verification; restricts mode transitions
- **Transition**: From User Mode by setting DeployedMode=1, or from Audit Mode by setting PK
- **Use Case**: Production systems with locked-down security policy

**Audit Mode**
- **Condition**: AuditMode=1, which clears PK and sets SetupMode=1
- **Behavior**: Logs signature verification failures without blocking boot; used for diagnostics
- **Use Case**: Testing signature verification without enforcement

#### NVRAM State Storage

UEFI variables are stored in NVRAM (Non-Volatile RAM) emulated by the OVMF_VARS.fd file:

**Key Variables**:
- **PK** (Platform Key): Root of trust; only one allowed; absence indicates Setup Mode
- **KEK** (Key Exchange Key): Signs updates to db/dbx; verified against PK
- **db** (Signature Database): Certificates allowed to sign operating systems (e.g., Microsoft UEFI CA)
- **dbx** (Forbidden Signature Database): Revoked signatures blacklist

**Status Variables**:
- **SetupMode**: 8-bit unsigned integer (1=setup mode, 0=user/deployed mode)
- **SecureBoot**: 8-bit unsigned integer (1=verification active, 0=not active)
- **DeployedMode**: Read-only when set to 1
- **AuditMode**: When set to 1, enables audit logging

**Default Variables** (Recovery):
- **PKDefault**, **KEKDefault**, **dbDefault**: Platform-defined defaults for OEM recovery

### Rationale

**Why Setup Mode is Required for Keystone**:
1. **Custom Key Enrollment**: Keystone uses lanzaboote which requires enrolling custom Secure Boot keys during installation
2. **Testing Flexibility**: Developers need to test the entire key enrollment process, not just booting with pre-enrolled keys
3. **Self-Sovereignty**: Aligns with Keystone's principle of cryptographic sovereignty - users control their trust anchors
4. **Installer Compatibility**: The Keystone installer needs to boot unsigned (or signed with custom keys) to perform initial setup

**Why Not User Mode with Pre-enrolled Keys**:
- Pre-enrolled Microsoft/vendor keys would reject the Keystone installer
- Doesn't allow testing the full Secure Boot setup workflow
- Violates the principle of users controlling their security infrastructure

### Alternatives Considered

**Alternative 1: Disable Secure Boot Entirely**
- **Approach**: Use non-secure OVMF firmware (edk2-x86_64-code.fd without "secure")
- **Rejected**: Doesn't test Secure Boot functionality; can't verify lanzaboote integration
- **When to use**: Only for systems that don't require Secure Boot

**Alternative 2: Pre-enroll Custom Keys in VARS Template**
- **Approach**: Use ovmfvartool to generate OVMF_VARS.fd with Keystone's keys pre-enrolled
- **Rejected**: Adds complexity; doesn't test the installer's key enrollment process; requires maintaining custom VARS templates
- **When to use**: Automated testing where key enrollment is already validated

**Alternative 3: User Mode with Microsoft Keys**
- **Approach**: Use OVMF_VARS.ms.fd with pre-enrolled Microsoft certificates
- **Rejected**: Keystone installer would fail to boot (not signed by Microsoft); doesn't enable self-sovereign key management
- **When to use**: Running Windows or vendor-signed Linux distributions

### References

- **UEFI Specification 2.10**: [Section 32 - Secure Boot and Driver Signing](https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
- **NSA Cybersecurity Report**: [UEFI Secure Boot Customization](https://media.defense.gov/2023/Mar/20/2003182401/-1/-1/0/CTR-UEFI-SECURE-BOOT-CUSTOMIZATION-20230317.PDF)
- **Arch Wiki**: [Unified Extensible Firmware Interface/Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
- **bootctl man page**: Details on Secure Boot status reporting

---

## 2. NixOS OVMF Firmware Variants

### Decision

Use the edk2 firmware files provided by NixOS QEMU package:
- **CODE**: `/nix/store/.../qemu-.../share/qemu/edk2-x86_64-secure-code.fd` (3.7MB)
- **VARS**: `/nix/store/.../qemu-.../share/qemu/edk2-i386-vars.fd` (541KB)

These files are located dynamically by the current bin/virtual-machine script using the `find_ovmf_firmware()` function.

### Technical Details

#### Available Firmware Files in NixOS

**QEMU Package** (Primary Source - Used by bin/virtual-machine):
```
/nix/store/{hash}-qemu-{version}/share/qemu/
├── edk2-x86_64-secure-code.fd   # 3.7MB - Secure Boot enabled firmware
├── edk2-x86_64-code.fd          # 3.7MB - Standard firmware (no Secure Boot)
├── edk2-i386-secure-code.fd     # 3.7MB - i386 Secure Boot firmware
├── edk2-i386-code.fd            # 3.7MB - i386 standard firmware
└── edk2-i386-vars.fd            # 541KB - Variables template (setup mode)
```

**OVMF.fd Package** (Secondary Source):
```
/nix/store/{hash}-OVMF-{version}-fd/FV/
├── OVMF_CODE.fd                 # 3.7MB - Firmware code
├── OVMF_VARS.fd                 # 541KB - Variables template
└── OVMF.fd                      # 4.2MB - Combined firmware (code+vars)
```

**OVMF Full Package** (Build-time only):
```
/nix/store/{hash}-OVMF-{version}/
├── FV/MEMFD.fd                  # 16MB - Development firmware
└── X64/                         # Build artifacts
```

**OVMFFull Package** (Available but not used):
- Contains full build artifacts including debug symbols
- Not suitable for runtime VM usage

#### Firmware File Differences

**CODE Files (Read-only firmware)**:
- **edk2-x86_64-secure-code.fd**: Secure Boot support compiled in; requires SMM
- **edk2-x86_64-code.fd**: No Secure Boot; smaller attack surface
- **OVMF_CODE.fd**: Similar to edk2-x86_64-code.fd; legacy naming
- **Size**: All CODE files are ~3.7MB

**VARS Files (Writable NVRAM templates)**:
- **edk2-i386-vars.fd**: Empty variable store (setup mode)
- **OVMF_VARS.fd**: Empty variable store (setup mode) - same size as edk2-i386-vars.fd
- **OVMF_VARS.ms.fd**: Pre-enrolled Microsoft keys (not currently in NixOS QEMU, available in OVMF package)
- **Size**: 541KB (540,672 bytes) - identical for all empty VARS

**Key Insight**: Both edk2-i386-vars.fd and OVMF_VARS.fd are byte-identical when empty (same 540,672 bytes), consisting mostly of 0xFF padding with minimal firmware volume headers. No pre-enrolled keys detected in hexdump analysis.

#### NixOS OVMF Package Status

**Historical Context** (GitHub Issue #288184):
- **Problem**: Neither OVMF.fd nor OVMFFull.fd provided Secure Boot-compatible firmware
- **Solution**: PR #284874 merged (Feb 2024) - enabled MS-compatible Secure Boot support
- **Current Status**: Closed as completed; QEMU package now includes edk2-*-secure-code.fd files

**Package Build Options**:
- `secureBoot = true`: Enables `-D SECURE_BOOT_ENABLE=TRUE` build flag
- `msVarsTemplate = true`: Creates OVMF_VARS.ms.fd with Microsoft keys (requires secureBoot=true)
- `fdSize4MB = true`: Required for Secure Boot (default for x86)
- `systemManagementModeRequired = true`: Automatically enabled with secureBoot on x86

**Current NixOS QEMU Configuration**:
- QEMU 9.2.4 (as of research date)
- Includes edk2 Secure Boot firmware files
- No .ms.fd (Microsoft keys) variant in QEMU package - requires separate OVMF build

### Rationale

**Why edk2-x86_64-secure-code.fd + edk2-i386-vars.fd**:
1. **Available by Default**: Included in standard QEMU package on NixOS
2. **Setup Mode by Default**: edk2-i386-vars.fd has no pre-enrolled keys (verified via hexdump)
3. **Consistent Paths**: Discovered automatically via bin/virtual-machine's `find_ovmf_firmware()` function
4. **Secure Boot Ready**: edk2-x86_64-secure-code.fd compiled with Secure Boot support
5. **Minimal Dependencies**: No need to build custom OVMF package

**Why Not OVMF_VARS.ms.fd**:
- Contains pre-enrolled Microsoft keys (PK, KEK, db)
- Would start in User Mode, not Setup Mode
- Not needed for custom key enrollment workflow

### Alternatives Considered

**Alternative 1: Use OVMF Package OVMF_CODE.fd + OVMF_VARS.fd**
- **Approach**: Use /nix/store/.../OVMF-.../FV/OVMF_CODE.fd
- **Pros**: Legacy naming may be familiar; same file format
- **Cons**: Requires additional package; QEMU files are preferred and already available
- **Decision**: Rejected - QEMU package is already a dependency

**Alternative 2: Build Custom OVMF with msVarsTemplate**
- **Approach**: Create a custom OVMF package with `secureBoot = true; msVarsTemplate = true;`
- **Pros**: Could generate OVMF_VARS.ms.fd for testing Windows or vendor-signed Linux
- **Cons**: Adds build complexity; not needed for setup mode; violates NixOS minimal dependency principle
- **Decision**: Rejected - use standard QEMU package

**Alternative 3: Use ovmfvartool to Generate Custom VARS**
- **Approach**: Use Python package ovmfvartool to parse/generate OVMF_VARS.fd from YAML
- **Pros**: Maximum flexibility; could pre-enroll Keystone keys
- **Cons**: Runtime dependency; complex; doesn't test installer key enrollment
- **Decision**: Rejected - copying empty VARS is simpler and sufficient

**Alternative 4: Download Debian's OVMF Files**
- **Approach**: Fetch OVMF_CODE_4M.secboot.fd and OVMF_VARS_4M.ms.fd from Debian
- **Pros**: Known working configuration
- **Cons**: External dependency; breaks NixOS reproducibility; not needed
- **Decision**: Rejected - NixOS provides equivalent files

### References

- **NixOS OVMF Package**: [nixpkgs/pkgs/applications/virtualization/OVMF/default.nix](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/virtualization/OVMF/default.nix)
- **GitHub Issue #288184**: [Provide OVMF files for secure boot](https://github.com/NixOS/nixpkgs/issues/288184) (Closed - resolved)
- **PR #284874**: Enable MS-compatible secure boot with OVMF (Merged Feb 2024)
- **Kraxel's Blog**: [EDK2 and firmware packaging](https://www.kraxel.org/blog/2022/07/edk2-firmware-packaging/)

---

## 3. NVRAM Initialization Best Practices

### Decision

**Approach for bin/virtual-machine**:
1. Copy edk2-i386-vars.fd template to `vms/{vm-name}/OVMF_VARS.fd` (already implemented)
2. Use modern libvirt XML features (libvirt 8.6+) to explicitly request setup mode
3. Verify firmware supports Secure Boot (check for "secure" in CODE filename)
4. Document verification using `bootctl status` showing "Secure Boot: disabled (setup)"

**Recommended XML Configuration**:
```xml
<os firmware='efi'>
  <firmware>
    <feature enabled='yes' name='secure-boot'/>
    <feature enabled='no' name='enrolled-keys'/>
  </firmware>
</os>
```

**Fallback XML Configuration** (libvirt < 8.6):
```xml
<os>
  <type arch='x86_64' machine='q35'>hvm</type>
  <loader readonly='yes' secure='yes' type='pflash'>{ovmf_code_path}</loader>
  <nvram template='{ovmf_vars_path}'>{vm_nvram_path}</nvram>
</os>
```

### Technical Details

#### Current bin/virtual-machine Implementation

**Existing Code (Lines 160-164)**:
```python
# Copy OVMF vars template to VM-specific NVRAM
if not os.path.exists(nvram_path):
    os.makedirs(os.path.dirname(nvram_path), exist_ok=True)
    os.system(f"cp {ovmf_vars} {nvram_path}")
    print(f"✓ Created NVRAM: {nvram_path}")
```

**Analysis**:
- ✅ Correctly copies OVMF_VARS template to VM directory
- ✅ Only copies if NVRAM doesn't exist (preserves state across reboots)
- ✅ Uses discovered ovmf_vars path (edk2-i386-vars.fd from QEMU)
- ⚠️ No verification that VARS template is in setup mode
- ⚠️ Uses legacy XML configuration without `firmware='efi'` features

**Existing XML (Lines 177-189)**:
```xml
<os>
  <type arch='x86_64' machine='q35'>hvm</type>
  <loader readonly='yes' secure='yes' type='pflash'>{ovmf_code}</loader>
  <nvram>{nvram_path}</nvram>
  <boot dev='hd'/>
</os>
```

**Analysis**:
- ✅ Uses `secure='yes'` to enable Secure Boot in firmware
- ✅ Uses q35 machine type (required for SMM)
- ✅ Uses pflash loader type
- ⚠️ Missing `template` attribute on `<nvram>` element
- ⚠️ Doesn't use modern `firmware='efi'` auto-selection
- ⚠️ Doesn't explicitly request `enrolled-keys='no'`

**Existing SMM Configuration (Lines 194-197)**:
```xml
<smm state='on'>
  <tseg unit='MiB'>48</tseg>
</smm>
```

**Analysis**:
- ✅ SMM (System Management Mode) enabled - required for Secure Boot
- ✅ TSEG set to 48MB - sufficient for large guests (240 vCPUs, 4TB RAM)
- ✅ Located in `<features>` section as required

#### Libvirt Firmware Auto-Selection

**Modern Approach (libvirt 8.6+)**:
- Libvirt auto-selects firmware based on features requested
- Uses firmware descriptor JSON files in `/usr/share/qemu/firmware/`
- Features: `secure-boot`, `enrolled-keys`, `requires-smm`
- `enrolled-keys='no'` explicitly requests setup mode

**Benefits**:
- Simpler XML configuration
- Libvirt validates firmware compatibility
- Automatic SMM configuration when needed
- Better error messages for misconfiguration

**Drawback**:
- Requires libvirt 8.6+ (available on recent NixOS)
- Auto-selection may choose unexpected firmware if descriptors are misconfigured
- Less explicit control over exact firmware files used

#### NVRAM State Management

**NVRAM Lifecycle**:
1. **Initial Creation**: Copy template to VM-specific path (vms/{vm-name}/OVMF_VARS.fd)
2. **VM Boot**: OVMF firmware reads/writes NVRAM file
3. **Key Enrollment**: Installer modifies NVRAM (PK/KEK/db/dbx variables)
4. **Mode Transition**: SetupMode=0, SecureBoot=1 after PK enrollment
5. **Persistence**: NVRAM file persists across reboots, maintaining state

**State Preservation**:
- NVRAM must not be re-copied after initial creation
- State persists in vms/{vm-name}/OVMF_VARS.fd
- Deleting NVRAM file resets to setup mode (useful for testing)

**Reset to Setup Mode**:
```bash
# Method 1: Delete NVRAM file (current approach)
rm vms/{vm-name}/OVMF_VARS.fd
# VM creation will copy fresh template

# Method 2: Clear PK variable (from within VM)
# Requires booting into UEFI firmware setup

# Method 3: Use virsh --reset-nvram (libvirt 8.1+)
virsh start {vm-name} --reset-nvram
```

### Rationale

**Why Hybrid Approach (Copy + Modern XML)**:
1. **Explicit Control**: Copying template ensures we know exactly what VARS file is used
2. **Future-Proof**: Modern XML features are clearer and more maintainable
3. **Backward Compatible**: Fallback to manual paths works with older libvirt
4. **Verifiable**: Can inspect NVRAM file on disk before VM starts

**Why Not Rely Solely on libvirt Auto-Selection**:
- NixOS firmware descriptor paths may differ from standard Linux
- Auto-selection can be unpredictable if firmware metadata is incorrect
- Explicit file paths provide better error messages
- Current script already discovers correct paths reliably

**Why Template Attribute Matters**:
- Without `template` attribute, libvirt doesn't know source of NVRAM
- With template, `virsh start --reset-nvram` can restore original state
- Provides libvirt context for managing NVRAM lifecycle

### Alternatives Considered

**Alternative 1: Use Only firmware='efi' Auto-Selection**
- **Approach**: Remove explicit `<loader>` and `<nvram>` paths, rely on libvirt
- **Pros**: Simpler XML; libvirt handles firmware discovery
- **Cons**: Less control; may select wrong firmware; harder to debug
- **Decision**: Rejected - Keep explicit paths for NixOS compatibility

**Alternative 2: Validate VARS File for Pre-enrolled Keys**
- **Approach**: Use ovmfvartool or hexdump to verify no PK is present before copying
- **Pros**: Guarantees setup mode; defensive programming
- **Cons**: Runtime dependency (ovmfvartool) or fragile hexdump parsing; overcomplicated
- **Decision**: Rejected - Trust NixOS QEMU package; add verification as future enhancement

**Alternative 3: Generate VARS from YAML Template**
- **Approach**: Ship YAML describing empty NVRAM; generate .fd file at runtime
- **Pros**: Human-readable; version-controllable; flexible
- **Cons**: Requires ovmfvartool; slower; unnecessary complexity
- **Decision**: Rejected - Copying template is simpler and sufficient

**Alternative 4: Use Static NVRAM Path (No Per-VM Copy)**
- **Approach**: Point all VMs at same OVMF_VARS template (read-only)
- **Pros**: No file copying needed
- **Cons**: NVRAM state not persistent; can't enroll keys; breaks Secure Boot workflow
- **Decision**: Rejected - NVRAM must be writable per-VM

### Implementation Recommendations

**Recommended Changes to bin/virtual-machine**:

1. **Add Template Attribute to NVRAM** (Line 186):
```python
<nvram template='{ovmf_vars}'>{nvram_path}</nvram>
```

2. **Add Optional Modern XML Support** (detect libvirt version, use if 8.6+):
```python
# Check libvirt version
libvirt_version = conn.getLibVersion()  # Returns integer (e.g., 8006000 for 8.6.0)

if libvirt_version >= 8006000:
    # Use modern firmware auto-selection
    os_xml = f"""
    <os firmware='efi'>
      <firmware>
        <feature enabled='yes' name='secure-boot'/>
        <feature enabled='no' name='enrolled-keys'/>
      </firmware>
      <boot dev='hd'/>
      {"<boot dev='cdrom'/>" if iso_path else ""}
    </os>
    """
else:
    # Use legacy manual configuration (current approach)
    os_xml = f"""
    <os>
      <type arch='x86_64' machine='q35'>hvm</type>
      <loader readonly='yes' secure='yes' type='pflash'>{ovmf_code}</loader>
      <nvram template='{ovmf_vars}'>{nvram_path}</nvram>
      <boot dev='hd'/>
      {"<boot dev='cdrom'/>" if iso_path else ""}
    </os>
    """
```

3. **Add NVRAM State Verification Helper**:
```python
def verify_setup_mode(nvram_path):
    """
    Check if NVRAM file appears to be in setup mode (no PK enrolled)
    Returns True if file doesn't exist or looks like empty template
    """
    if not os.path.exists(nvram_path):
        return True  # Will be created from template

    # Check file size matches expected empty VARS (540,672 bytes)
    stat = os.stat(nvram_path)
    return stat.st_size == 540672  # Exact size of empty edk2-i386-vars.fd
```

4. **Enhance Verification Instructions** (Lines 473-477):
```python
print("\n🔒 VERIFY SECURE BOOT SETUP MODE:")
print("  Inside the VM after booting from installer ISO:")
print("    bootctl status | grep 'Secure Boot'")
print("    Expected output: 'Secure Boot: disabled (setup)'")
print("  Manual check (if bootctl unavailable):")
print("    od --address-radix=n --format=u1 /sys/firmware/efi/efivars/SetupMode-*")
print("    Expected: last byte is 1 (setup mode)")
```

### References

- **libvirt Secure Boot Guide**: [libvirt.org/kbase/secureboot.html](https://libvirt.org/kbase/secureboot.html)
- **libvirt Domain XML Format**: [libvirt.org/formatdomain.html](https://libvirt.org/formatdomain.html)
- **OpenStack Nova Secure Boot Spec**: [specs.openstack.org/.../allow-secure-boot-for-qemu-kvm-guests](https://specs.openstack.org/openstack/nova-specs/specs/wallaby/approved/allow-secure-boot-for-qemu-kvm-guests.html)
- **Testing SMM with QEMU**: [tianocore.github.io/wiki/Testing-SMM-with-QEMU,-KVM-and-libvirt](https://github.com/tianocore/tianocore.github.io/wiki/Testing-SMM-with-QEMU,-KVM-and-libvirt)

---

## 4. Verification Methods

### Decision

**Primary Verification**: Use `bootctl status` from within the VM
- Shows "Secure Boot: disabled (setup)" for setup mode
- Shows "Secure Boot: enabled (user)" after key enrollment
- Available in NixOS installer environment (systemd-based)

**Secondary Verification**: Manual efivars inspection
- Check `/sys/firmware/efi/efivars/SetupMode-*` (should be 1)
- Check `/sys/firmware/efi/efivars/SecureBoot-*` (should be 0)
- Use `od --address-radix=n --format=u1` to read variable

**Development Verification**: NVRAM file inspection
- Check file size (540,672 bytes = empty template)
- Use hexdump to verify no Microsoft/vendor keys present
- Optional: Use ovmfvartool to dump variables

### Technical Details

#### bootctl Status Output

**Setup Mode Example**:
```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Firmware Arch: x64
    Secure Boot: disabled (setup)              ← Target state
   TPM2 Support: yes
   Boot into FW: supported
```

**Key Indicators**:
- **"disabled (setup)"**: Setup mode - Secure Boot firmware present but no keys enrolled
- **"disabled (disabled)"**: Secure Boot not supported by firmware
- **"enabled (user)"**: User mode - keys enrolled, signature verification active
- **"disabled (unsupported)"**: Firmware doesn't support Secure Boot

**User Mode Example** (After Key Enrollment):
```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Firmware Arch: x64
    Secure Boot: enabled (user)                ← After PK enrollment
   TPM2 Support: yes
```

#### How bootctl Determines Secure Boot Mode

**Source Analysis** (systemd-boot codebase):
1. Reads `/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c`
2. Reads `/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c`
3. Reads `/sys/firmware/efi/efivars/DeployedMode-8be4df61-93ca-11d2-aa0d-00e098032b8c` (if available)

**Logic**:
- If SecureBoot=1: "enabled (user or deployed)"
- If SecureBoot=0 and SetupMode=1: "disabled (setup)"
- If SecureBoot=0 and SetupMode=0: "disabled (disabled)"
- If variables don't exist: "disabled (unsupported)"

**Variable GUIDs**:
- All Secure Boot variables use EFI_GLOBAL_VARIABLE GUID: `8be4df61-93ca-11d2-aa0d-00e098032b8c`

#### Manual efivars Verification

**Check SetupMode**:
```bash
# Method 1: Using od (octal dump)
od --address-radix=n --format=u1 \
  /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c

# Expected output (setup mode):
# ... 7 0 0 0 1
#           ↑ Last byte is 1 (setup mode)

# Method 2: Using hexdump
hexdump -C /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
# Look for final byte: 01 (setup mode) or 00 (user mode)
```

**Check SecureBoot**:
```bash
od --address-radix=n --format=u1 \
  /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c

# Expected output (setup mode):
# ... 7 0 0 0 0
#           ↑ Last byte is 0 (not enforcing)
```

**Variable Format**:
```
Bytes 0-3:  Attributes (little-endian uint32)
Bytes 4+:   Data (1 byte for SetupMode/SecureBoot)
```

**Common Attributes**:
- `0x00000007`: NON_VOLATILE | BOOTSERVICE_ACCESS | RUNTIME_ACCESS

#### Alternative Verification Methods

**Using mokutil** (Machine Owner Key utility):
```bash
mokutil --sb-state
# Output: "SecureBoot enabled" or "SecureBoot disabled"
# Note: May not distinguish setup mode from disabled
```

**Using dmesg**:
```bash
dmesg | grep -i 'secure boot'
# Setup mode: No "secureboot: Secure Boot enabled" message
# User mode:  "secureboot: Secure Boot enabled"
#             "Kernel is locked down from EFI Secure Boot mode"
```

**Using efivar tool**:
```bash
efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode
# Output: value in hex (01 = setup mode, 00 = user mode)
```

#### NVRAM File Inspection (Development)

**File Size Check**:
```bash
stat -c "%s" vms/keystone-test-vm/OVMF_VARS.fd
# Expected: 540672 bytes (empty template)
# Larger size may indicate enrolled keys (though size alone isn't definitive)
```

**Hexdump for Keys**:
```bash
hexdump -C vms/keystone-test-vm/OVMF_VARS.fd | grep -i "microsoft\|canonical"
# Empty output = no vendor keys found
# Output with key names = keys may be enrolled
```

**Using ovmfvartool** (requires nixpkgs.python3Packages.ovmfvartool):
```bash
nix shell nixpkgs#python3Packages.ovmfvartool
ovmfvartool dump vms/keystone-test-vm/OVMF_VARS.fd

# Example output (setup mode):
# No PK, KEK, db, or dbx variables present
# Only internal OVMF variables

# Example output (enrolled keys):
# Variable: PK (Platform Key)
# Variable: KEK (Key Exchange Key)
# Variable: db (Signature Database)
# Variable: dbx (Forbidden Signature Database)
```

### Rationale

**Why bootctl is Primary Verification**:
1. **User-Friendly**: Clear, human-readable output
2. **Available in Installer**: NixOS installer includes systemd-boot tools
3. **Comprehensive**: Shows all relevant Secure Boot information
4. **Reliable**: Directly reads UEFI variables; not guessing based on file size
5. **Documented**: Well-known tool with consistent output format

**Why Manual efivars is Secondary**:
- Works even without bootctl installed
- Educational - shows underlying mechanism
- Useful for debugging when bootctl output is unclear
- Required for non-systemd-based systems

**Why NVRAM File Inspection is Development-Only**:
- Can't reliably determine mode from file alone (keys may be same size as empty space)
- Requires VM to be shut down
- Hexdump parsing is fragile
- Useful for pre-flight checks before VM starts

### Alternatives Considered

**Alternative 1: Use mokutil --sb-state**
- **Pros**: Simple one-line command
- **Cons**: May not distinguish setup mode from disabled; not always available in installers
- **Decision**: Supplement to bootctl, not replacement

**Alternative 2: Parse dmesg for Secure Boot Messages**
- **Pros**: Kernel-level confirmation; shows lock-down status
- **Cons**: Negative indicator only (absence of message); not conclusive for setup mode
- **Decision**: Useful for post-boot verification, not primary method

**Alternative 3: UEFI Shell efivar Command**
- **Pros**: Direct UEFI variable access; works in firmware
- **Cons**: Requires booting to UEFI shell; not practical for automated testing
- **Decision**: Rejected - OS-level tools are more practical

**Alternative 4: Custom Python Script Using python-efivar**
- **Pros**: Programmatic access; could automate testing
- **Cons**: Requires additional dependencies; OS must be booted; overcomplicated
- **Decision**: Rejected - bootctl is sufficient and already available

### Implementation Recommendations

**Documentation Addition to bin/virtual-machine**:

```python
def print_verification_guide():
    """Print comprehensive verification instructions"""
    print("\n" + "="*70)
    print("SECURE BOOT SETUP MODE VERIFICATION")
    print("="*70)

    print("\n1️⃣  PRIMARY METHOD - Using bootctl:")
    print("    Boot the VM from the Keystone installer ISO, then run:")
    print("      bootctl status | grep 'Secure Boot'")
    print()
    print("    Expected output for setup mode:")
    print("      Secure Boot: disabled (setup)")
    print()
    print("    After enrolling keys (post-installation):")
    print("      Secure Boot: enabled (user)")

    print("\n2️⃣  SECONDARY METHOD - Manual efivars check:")
    print("    If bootctl is unavailable, check UEFI variables directly:")
    print("      od --address-radix=n --format=u1 \\")
    print("        /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c")
    print()
    print("    Expected output (setup mode):")
    print("      ... 7 0 0 0 1")
    print("                ↑ Last byte is 1")

    print("\n3️⃣  ADDITIONAL CHECKS:")
    print("    • dmesg | grep -i 'secure boot'")
    print("      Setup mode: No 'Secure Boot enabled' message")
    print("    • mokutil --sb-state")
    print("      (May not distinguish setup from disabled)")

    print("\n📋 TROUBLESHOOTING:")
    print("  If bootctl shows 'disabled (disabled)' instead of 'disabled (setup)':")
    print("    • Check firmware: Must use edk2-x86_64-secure-code.fd")
    print("    • Check NVRAM: Should be 540,672 bytes")
    print("    • Reset NVRAM: rm vms/{vm-name}/OVMF_VARS.fd && restart VM")
    print("="*70 + "\n")
```

**Add to --help Output**:
```python
parser.add_argument('--verify-setup-mode', action='store_true',
                    help='Print Secure Boot setup mode verification instructions')
```

### References

- **bootctl man page**: [freedesktop.org/software/systemd/man/bootctl.html](https://www.freedesktop.org/software/systemd/man/systemd-boot.html)
- **Arch Wiki - Secure Boot**: [wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
- **UEFI Spec 2.10 - Section 3.3**: EFI Variable Services
- **systemd-boot source**: Secure Boot status detection logic

---

## 5. Edge Cases and Error Handling

### Decision

Implement defensive checks and clear error messages for common failure modes:
1. **Missing OVMF Secure Boot firmware**: Fail fast with actionable error
2. **NVRAM corruption**: Detect and provide recovery instructions
3. **Pre-enrolled keys**: Warn if NVRAM file unexpectedly large
4. **libvirt version mismatch**: Graceful degradation for older libvirt
5. **Firmware doesn't support Secure Boot**: Early detection and clear message

### Technical Details

#### Edge Case 1: OVMF_VARS Template Has Pre-enrolled Keys

**Scenario**:
- User manually copies OVMF_VARS.ms.fd (Microsoft keys) to NVRAM path
- Or NixOS package unexpectedly includes pre-enrolled keys
- Or NVRAM file from previous VM has keys enrolled

**Detection**:
```python
def check_vars_template(vars_path):
    """
    Check if VARS file appears to have pre-enrolled keys
    Returns: (is_clean, warning_message)
    """
    if not os.path.exists(vars_path):
        return True, None

    # Empty template should be exactly 540,672 bytes
    expected_size = 540672
    actual_size = os.path.getsize(vars_path)

    if actual_size > expected_size + 10000:  # Allow 10KB variance for metadata
        warning = (
            f"⚠️  WARNING: NVRAM file is larger than expected\n"
            f"    Expected: ~{expected_size} bytes (empty template)\n"
            f"    Actual:   {actual_size} bytes\n"
            f"    This may indicate pre-enrolled keys.\n"
            f"    VM may NOT boot in setup mode.\n"
            f"    To reset: rm {vars_path}"
        )
        return False, warning

    return True, None
```

**Mitigation**:
- Check VARS file size before copying
- Log warning but don't block VM creation
- Document expected file size in error message
- Provide clear reset instructions

#### Edge Case 2: Firmware Doesn't Support Secure Boot

**Scenario**:
- `find_ovmf_firmware()` returns non-secure firmware (edk2-x86_64-code.fd)
- Or returns None (no OVMF firmware found)
- VM boots but bootctl shows "disabled (unsupported)"

**Current Check (Lines 167-172)**:
```python
if "secure" not in ovmf_code.lower():
    print("ERROR: Secure Boot firmware not found!")
    print("This script requires Secure Boot enabled OVMF firmware.")
    print(f"Found: {ovmf_code}")
    print("On NixOS, ensure QEMU is installed with EDK2 Secure Boot firmware.")
    sys.exit(1)
```

**Enhancement**:
```python
def validate_secure_boot_firmware(code_path, vars_path):
    """
    Validate that firmware supports Secure Boot
    Returns: (is_valid, error_message)
    """
    if not code_path or not vars_path:
        return False, (
            "ERROR: OVMF firmware not found!\n"
            "On NixOS, ensure QEMU is installed:\n"
            "  nix-shell -p qemu\n"
            "Or add to configuration.nix:\n"
            "  virtualisation.libvirtd.enable = true;"
        )

    # Check for Secure Boot support in CODE filename
    if "secure" not in os.path.basename(code_path).lower():
        return False, (
            f"ERROR: Secure Boot firmware not found!\n"
            f"Found CODE: {code_path}\n"
            f"Expected: edk2-x86_64-secure-code.fd or OVMF_CODE.secboot.fd\n"
            f"Current firmware does not support Secure Boot.\n"
            f"On NixOS, ensure you have QEMU with EDK2 Secure Boot firmware."
        )

    # Check VARS file exists and is readable
    if not os.access(vars_path, os.R_OK):
        return False, (
            f"ERROR: VARS template not readable!\n"
            f"Path: {vars_path}\n"
            f"Check file permissions."
        )

    return True, None
```

#### Edge Case 3: NVRAM Corruption

**Scenario**:
- NVRAM file exists but is corrupted (truncated, random data)
- libvirt fails to start VM with cryptic error
- OVMF firmware resets NVRAM to defaults (may not be setup mode)

**Detection**:
```python
def validate_nvram_file(nvram_path):
    """
    Check if NVRAM file appears valid
    Returns: (is_valid, error_message)
    """
    if not os.path.exists(nvram_path):
        return True, None  # Will be created from template

    size = os.path.getsize(nvram_path)

    # Check minimum size (must be at least firmware volume header size)
    min_size = 65536  # 64KB minimum
    if size < min_size:
        return False, (
            f"ERROR: NVRAM file appears corrupted (too small)\n"
            f"Path: {nvram_path}\n"
            f"Size: {size} bytes (expected >= {min_size})\n"
            f"To fix: rm {nvram_path}"
        )

    # Check file is not all zeros or all 0xFF
    with open(nvram_path, 'rb') as f:
        sample = f.read(1024)
        if sample == b'\x00' * 1024 or sample == b'\xff' * 1024:
            return False, (
                f"WARNING: NVRAM file appears corrupted (uniform data)\n"
                f"Path: {nvram_path}\n"
                f"To fix: rm {nvram_path}"
            )

    return True, None
```

**Recovery**:
- Delete corrupted NVRAM file
- VM creation will copy fresh template
- Document recovery in error message

#### Edge Case 4: VM Already Transitioned Out of Setup Mode

**Scenario**:
- Developer creates VM, boots installer, enrolls keys
- Later wants to test key enrollment again
- NVRAM persists enrolled keys; VM not in setup mode

**Detection**:
- Can't detect reliably without booting VM
- File size won't change (keys may be same size as empty space)

**Solution**:
```python
def reset_vm_to_setup_mode(vm_name):
    """
    Reset VM NVRAM to setup mode (delete and recreate)
    """
    try:
        dom = conn.lookupByName(vm_name)
        if dom.isActive():
            print(f"ERROR: VM '{vm_name}' is running!")
            print("Shut down VM first: virsh shutdown {vm_name}")
            return False

        # Get NVRAM path from XML
        xml = dom.XMLDesc(0)
        root = ET.fromstring(xml)
        nvram = root.find('.//os/nvram')

        if nvram is not None and nvram.text:
            nvram_path = nvram.text
            if os.path.exists(nvram_path):
                os.remove(nvram_path)
                print(f"✓ Deleted NVRAM: {nvram_path}")
                print(f"✓ VM will start in setup mode on next boot")
                return True

        print("WARNING: Could not find NVRAM path in VM XML")
        return False

    except libvirt.libvirtError as e:
        print(f"ERROR: {e}")
        return False
```

**Add CLI Option**:
```python
parser.add_argument('--reset-setup-mode', metavar='VM_NAME',
                    help='Reset VM to Secure Boot setup mode (delete NVRAM)')
```

#### Edge Case 5: libvirt Version Too Old

**Scenario**:
- User has libvirt < 5.3 (no firmware auto-selection)
- Or libvirt < 8.6 (no enrolled-keys feature)
- Modern XML features fail with error

**Detection**:
```python
def check_libvirt_version(conn):
    """
    Check libvirt version and report capabilities
    Returns: (version_int, capabilities_dict)
    """
    version = conn.getLibVersion()  # e.g., 8006000 for 8.6.0
    major = version // 1000000
    minor = (version % 1000000) // 1000
    patch = version % 1000

    capabilities = {
        'auto_firmware': version >= 5003000,      # 5.3.0+
        'enrolled_keys': version >= 8006000,      # 8.6.0+
        'reset_nvram': version >= 8001000,        # 8.1.0+
    }

    print(f"✓ libvirt version: {major}.{minor}.{patch}")

    if not capabilities['enrolled_keys']:
        print("ℹ Note: libvirt < 8.6.0 - using legacy XML configuration")
        print("  (Upgrade to 8.6+ for modern firmware auto-selection)")

    return version, capabilities
```

**Graceful Degradation**:
- Use legacy XML configuration for older libvirt
- Document version requirements
- Provide upgrade instructions for NixOS

#### Edge Case 6: Missing SMM Configuration

**Scenario**:
- XML has `<loader secure='yes'>` but no `<smm state='on'>`
- libvirt may auto-add SMM, or VM may fail to boot
- Secure Boot may not work correctly

**Prevention**:
```python
def validate_vm_config(xml_config):
    """
    Validate VM XML configuration for Secure Boot compatibility
    Returns: (is_valid, warnings)
    """
    warnings = []
    root = ET.fromstring(xml_config)

    # Check machine type
    os_type = root.find('.//os/type')
    if os_type is not None:
        machine = os_type.get('machine', '')
        if not machine.startswith('q35'):
            warnings.append(
                "WARNING: Machine type should be 'q35' for Secure Boot\n"
                f"Found: {machine}"
            )

    # Check SMM feature
    smm = root.find('.//features/smm')
    if smm is None or smm.get('state') != 'on':
        warnings.append(
            "WARNING: SMM (System Management Mode) should be enabled\n"
            "Required for Secure Boot on x86_64"
        )

    # Check loader secure attribute
    loader = root.find('.//os/loader')
    if loader is not None and loader.get('secure') != 'yes':
        warnings.append(
            "WARNING: Loader should have secure='yes' for Secure Boot"
        )

    return len(warnings) == 0, warnings
```

### Rationale

**Why Defensive Checks Matter**:
1. **Developer Experience**: Clear errors save debugging time
2. **Data Safety**: Detect corruption before it causes mysterious failures
3. **Reproducibility**: Consistent behavior across different NixOS versions
4. **Documentation**: Error messages teach users about requirements

**Why Not Fail Silently**:
- Silent failures lead to confusion ("Why isn't my VM in setup mode?")
- Explicit errors with recovery steps empower developers
- Matches NixOS philosophy of fail-fast with clear diagnostics

### Alternatives Considered

**Alternative 1: Auto-Fix All Issues**
- **Approach**: Automatically delete corrupted NVRAM, download missing firmware, etc.
- **Pros**: Zero-friction experience
- **Cons**: Hides problems; may mask configuration errors; surprising behavior
- **Decision**: Rejected - Explicit errors are better for understanding system state

**Alternative 2: Strict Mode (Fail on Any Warning)**
- **Approach**: Treat all warnings as errors; refuse to create VM
- **Pros**: Maximum safety; no ambiguous states
- **Cons**: Too strict; may prevent valid use cases; annoying for experts
- **Decision**: Rejected - Warnings should inform, not block

**Alternative 3: Interactive Prompts**
- **Approach**: Ask user to confirm actions ("NVRAM exists, overwrite? [y/N]")
- **Pros**: User control; educational
- **Cons**: Breaks automation; annoying for scripts; not suitable for CLI tool
- **Decision**: Rejected - Use flags instead (e.g., --reset-setup-mode)

### Implementation Recommendations

**Error Handling Flow**:
```python
def create_vm_with_setup_mode(conn, vm_config):
    """
    Create VM ensuring Secure Boot setup mode
    """
    # 1. Check libvirt version and capabilities
    version, capabilities = check_libvirt_version(conn)

    # 2. Validate firmware files
    is_valid, error = validate_secure_boot_firmware(
        vm_config['ovmf_code'],
        vm_config['ovmf_vars']
    )
    if not is_valid:
        print(error)
        sys.exit(1)

    # 3. Check VARS template for pre-enrolled keys
    is_clean, warning = check_vars_template(vm_config['ovmf_vars'])
    if not is_clean:
        print(warning)
        # Continue anyway, but warn user

    # 4. Validate existing NVRAM (if present)
    nvram_path = vm_config['nvram_path']
    is_valid, error = validate_nvram_file(nvram_path)
    if not is_valid:
        print(error)
        print("\nAttempting automatic recovery...")
        if os.path.exists(nvram_path):
            os.remove(nvram_path)
            print(f"✓ Deleted corrupted NVRAM: {nvram_path}")

    # 5. Copy VARS template if needed
    if not os.path.exists(nvram_path):
        os.makedirs(os.path.dirname(nvram_path), exist_ok=True)
        shutil.copy2(vm_config['ovmf_vars'], nvram_path)
        print(f"✓ Created NVRAM: {nvram_path}")

    # 6. Build XML configuration (modern or legacy based on version)
    xml_config = build_vm_xml(vm_config, capabilities)

    # 7. Validate configuration before submission
    is_valid, warnings = validate_vm_config(xml_config)
    for warning in warnings:
        print(warning)

    # 8. Create VM
    try:
        dom = conn.defineXML(xml_config)
        print(f"✓ VM '{vm_config['name']}' created successfully")
        print(f"✓ Secure Boot setup mode ready for testing")
        return dom
    except libvirt.libvirtError as e:
        print(f"ERROR: Failed to create VM: {e}")
        sys.exit(1)
```

### References

- **libvirt Error Handling**: [libvirt.org/errors.html](https://libvirt.org/errors.html)
- **OVMF Debug**: [tianocore.github.io/ovmf-whitepaper](https://www.linux-kvm.org/downloads/lersek/ovmf-whitepaper-c770f8c.txt)
- **UEFI Spec - Variable Services**: Error conditions for EFI variable operations

---

## Summary and Next Steps

### Key Findings

1. **OVMF Firmware**: NixOS QEMU package provides edk2-x86_64-secure-code.fd and edk2-i386-vars.fd, which are already in setup mode (no pre-enrolled keys)

2. **Current Implementation**: bin/virtual-machine already copies VARS template correctly; main improvement needed is adding libvirt XML features for explicit setup mode configuration

3. **Verification**: bootctl status is the recommended verification method, showing "Secure Boot: disabled (setup)" for correct configuration

4. **Edge Cases**: Most important: detecting pre-enrolled keys, handling corrupted NVRAM, and providing clear error messages for missing firmware

### Recommended Implementation Plan

**Phase 1: Minimal Changes** (Immediate)
1. Add `template` attribute to `<nvram>` element in XML
2. Enhance verification instructions in help text
3. Document expected bootctl output

**Phase 2: Robustness** (Next)
1. Add NVRAM file validation
2. Implement --reset-setup-mode flag
3. Add pre-flight checks for firmware and NVRAM state

**Phase 3: Modernization** (Future)
1. Add libvirt version detection
2. Use firmware='efi' with enrolled-keys='no' for libvirt 8.6+
3. Comprehensive error handling with recovery suggestions

### Testing Checklist

- [ ] Create new VM, verify NVRAM is 540,672 bytes
- [ ] Boot VM from Keystone installer ISO
- [ ] Run `bootctl status` and confirm "disabled (setup)"
- [ ] Test NVRAM persistence across VM reboots
- [ ] Test --reset-setup-mode functionality
- [ ] Verify error messages for missing firmware
- [ ] Test with corrupted NVRAM file
- [ ] Document all verification steps in bin/virtual-machine --help

### Open Questions

1. Should we add ovmfvartool as optional dependency for NVRAM inspection?
2. Should we implement automatic firmware version checking?
3. Should we provide a "strict mode" that validates setup mode before each boot?

---

**Research Completed**: 2025-10-31
**Next Steps**: Proceed to implementation plan (plan.md) and task breakdown (tasks.md)
