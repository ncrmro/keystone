# Secure Boot Integration with Disko

## Feature Overview

Integrate Secure Boot key generation and enrollment directly into the disko deployment process to enable fully functional Secure Boot from the first boot after nixos-anywhere deployment, eliminating the need for post-installation provisioning.

## Problem Statement

Currently, the Keystone deployment process requires:
1. Initial deployment with nixos-anywhere
2. VM reboot to installed system
3. Manual execution of post-install-provisioner script
4. Another reboot to activate Secure Boot

This multi-step process has several issues:
- Lanzaboote cannot sign the bootloader during initial deployment because keys don't exist yet
- The system boots insecurely on the first boot after installation
- Manual intervention is required to achieve full security
- The process is error-prone and difficult to automate

## Proposed Solution

Move Secure Boot key generation and enrollment into a disko hook that runs during nixos-anywhere deployment, before the NixOS configuration is built. This ensures:
- Keys are generated in the correct location (/var/lib/sbctl/keys) before NixOS builds
- Lanzaboote can sign the bootloader during initial system build
- First boot after installation has Secure Boot fully enabled
- No post-installation steps required

## User Requirements

### Functional Requirements

1. **Automatic Key Generation**
   - Generate Secure Boot keys (PK, KEK, db) during disko partitioning
   - Place keys in /var/lib/sbctl/keys on the target system
   - Support both custom-only and Microsoft-inclusive key sets

2. **Key Enrollment**
   - Enroll keys into UEFI firmware while in Setup Mode
   - Transition firmware from Setup Mode to User Mode
   - Handle enrollment failures gracefully

3. **Lanzaboote Integration**
   - Enable lanzaboote module in NixOS configuration
   - Ensure bootloader is signed during initial build
   - Support both VM and physical hardware deployments

4. **Verification**
   - Verify Secure Boot is enabled on first boot
   - Check that all boot components are properly signed
   - Provide clear status reporting

### Non-Functional Requirements

1. **Compatibility**
   - Must work with QEMU/KVM virtual machines in Setup Mode
   - Support physical UEFI systems
   - Compatible with TPM2 automatic disk unlock

2. **Security**
   - Keys must be generated securely with proper entropy
   - Keys should be protected with appropriate permissions
   - Support key backup/recovery mechanisms

3. **Reliability**
   - Handle Setup Mode detection properly
   - Gracefully handle already-enrolled systems
   - Provide clear error messages on failure

## Success Criteria

1. Single-command deployment: `nixos-anywhere --flake .#test-server root@<ip>`
2. First boot after deployment has Secure Boot enabled
3. No manual intervention required
4. Bootloader and kernel are properly signed
5. `bootctl status` shows "Secure Boot: enabled (user)"

## Technical Constraints

1. Must work within disko's hook system
2. sbctl must be available in the installer environment
3. UEFI firmware must be in Setup Mode initially
4. Keys must be generated before NixOS configuration build
5. Must integrate cleanly with existing Keystone modules

## Out of Scope

- Key rotation after initial deployment
- Migration of existing systems to Secure Boot
- Support for non-UEFI systems
- Custom certificate chains or external PKI integration
- Dual-boot scenarios with other operating systems

## Dependencies

- nixpkgs.sbctl package
- lanzaboote NixOS module (to be added as flake input)
- UEFI firmware with Setup Mode support
- systemd-boot bootloader
- disko partitioning tool

## Testing Requirements

1. VM deployment with bin/test-deployment should complete successfully
2. Secure Boot should be enabled on first boot (no reboot required)
3. System should boot normally with disk encryption
4. TPM2 automatic unlock should continue to work
5. Keys should be properly enrolled in firmware