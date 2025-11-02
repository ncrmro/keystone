# Research: Secure Boot Integration with Disko

## Phase 0 Research Findings

### 1. Lanzaboote Flake Integration

**Decision**: Add lanzaboote as a flake input and use its NixOS module
**Rationale**:
- Lanzaboote is the standard NixOS Secure Boot implementation
- Provides automatic bootloader signing with sbctl
- Integrates cleanly with systemd-boot
- Actively maintained by nix-community

**Alternatives Considered**:
- Direct sbctl usage: Too low-level, requires manual signing
- systemd-boot native signing: Not mature enough in NixOS
- GRUB with shim: More complex, less NixOS-native

**Implementation Details**:
```nix
# flake.nix additions
inputs.lanzaboote = {
  url = "github:nix-community/lanzaboote/v0.4.1";
  inputs.nixpkgs.follows = "nixpkgs";
};

# Module usage
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/var/lib/sbctl";
};
```

### 2. Disko Hook Execution Context

**Decision**: Use disko's `postCreateHook` on the root filesystem dataset
**Rationale**:
- Runs after partitioning but before NixOS installation
- Has access to mounted filesystem at /mnt
- Can create files that persist to installed system
- Executes in nixos-anywhere's build environment

**Alternatives Considered**:
- `preCreateHook`: Too early, filesystem not available
- systemd service: Too late, NixOS already built
- nixos-anywhere extra-files: Can't generate keys dynamically

**Key Findings**:
- Hook runs as root with full system access
- `/mnt` is the target filesystem root
- sbctl must be available in installer environment
- Can check UEFI variables at `/sys/firmware/efi/efivars`

### 3. Key Generation Timing

**Decision**: Generate and enroll keys in single postCreateHook
**Rationale**:
- Keys must exist before NixOS configuration evaluation
- Enrollment while in Setup Mode avoids reboot requirement
- Single atomic operation reduces failure points

**Alternatives Considered**:
- Two-phase (generate then enroll): Unnecessary complexity
- Post-build enrollment: Requires additional reboot
- Pre-generated keys: Violates security principles

**Implementation Strategy**:
1. Check Setup Mode status
2. Generate keys to `/mnt/var/lib/sbctl/keys`
3. Enroll keys immediately
4. Transition to User Mode
5. NixOS build proceeds with keys available

### 4. Installer Environment Requirements

**Decision**: Add sbctl to installer via iso-installer module
**Rationale**:
- sbctl needed for key generation in disko hook
- Must be available before NixOS installation
- ISO module already handles installer customization

**Alternatives Considered**:
- Runtime download: Network dependency, slower
- Embed in disko module: Wrong abstraction layer
- Custom installer derivation: Overly complex

### 5. Error Handling Strategy

**Decision**: Fail fast on Setup Mode violations, warn on enrollment issues
**Rationale**:
- Setup Mode is mandatory for initial deployment
- Enrollment failures might be recoverable
- Clear error messages guide troubleshooting

**Error Conditions**:
- Not in Setup Mode: Fatal error
- Key generation failure: Fatal error
- Enrollment failure: Warning with fallback
- Already enrolled: Skip with info message

### 6. Testing Approach

**Decision**: Extend bin/test-deployment to verify Secure Boot on first boot
**Rationale**:
- Existing test infrastructure with VM support
- Can verify end-to-end workflow
- Automated validation of success criteria

**Test Verification Points**:
1. Keys generated during deployment
2. No post-install-provisioner execution
3. First boot shows Secure Boot enabled
4. Bootloader properly signed
5. System boots successfully

## Technical Clarifications Resolved

### Q: How does lanzaboote find keys?
**A**: Uses `boot.lanzaboote.pkiBundle` option pointing to `/var/lib/sbctl`

### Q: When exactly do hooks run?
**A**: After partition creation, filesystem formatting, and mounting at `/mnt`

### Q: Can we detect Setup Mode in hooks?
**A**: Yes, via `/sys/firmware/efi/efivars/SetupMode-*` variable

### Q: Do keys persist across reinstalls?
**A**: No, regenerated each deployment (by design for security)

### Q: VM compatibility concerns?
**A**: OVMF firmware supports Setup Mode perfectly for testing

## Next Steps

With all technical clarifications resolved, we can proceed to Phase 1 design:
- Define module options and structure
- Create detailed implementation contracts
- Document usage patterns