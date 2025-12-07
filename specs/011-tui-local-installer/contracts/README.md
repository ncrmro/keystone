# API Contracts: TUI Local Installer

**Feature Branch**: `011-tui-local-installer`
**Date**: 2025-12-07

## Overview

This directory contains TypeScript API contracts defining the interfaces between TUI components and system operations. These contracts serve as the specification for implementation.

## Contract Files

### disk-operations.ts

Low-level disk detection and manipulation:
- `detectDisks()` - Enumerate available block devices
- `getByIdPath()` - Resolve stable device paths
- `validateDisk()` - Validate disk is suitable for installation
- `formatDiskEncrypted()` - Format with ZFS + LUKS encryption
- `formatDiskUnencrypted()` - Format with simple ext4
- `mountFilesystems()` - Mount to /mnt for installation
- `unmountFilesystems()` - Cleanup after installation
- `hasTPM2()` - Detect TPM2 availability

### config-generator.ts

NixOS configuration file generation:
- `generateConfiguration()` - Generate complete config directory
- `generateFlakeNix()` - Create flake.nix with Keystone inputs
- `generateHostDefaultNix()` - Create host-specific default.nix
- `generateDiskConfigEncrypted()` - Disko config for encrypted installs
- `generateDiskConfigUnencrypted()` - Disko config for plain installs
- `generateHardwareConfig()` - Run nixos-generate-config
- `initGitRepository()` - Initialize git in config directory
- `validateHostname()` - Validate hostname format (RFC 1123)
- `validateUsername()` - Validate username format (POSIX)

### installation.ts

Installation orchestration and progress tracking:
- `runInstallation()` - Complete installation workflow
- `partitionDisk()` - Create disk partitions
- `formatDisk()` - Format partitions
- `mountForInstall()` - Mount filesystems
- `runNixosInstall()` - Execute nixos-install
- `copyConfigToInstalled()` - Copy config to target system
- `cleanup()` - Unmount and cleanup
- `cloneRepository()` - Git clone for repository method
- `validateGitUrl()` - Validate repository URL
- `logOperation()` - Write to installation log
- `getInstallationSummary()` - Generate summary for display

## Usage in TUI

The TUI application (App.tsx) will import and use these contracts:

```typescript
import { detectDisks, validateDisk, hasTPM2 } from './disk-operations';
import { generateConfiguration, validateHostname } from './config-generator';
import { runInstallation, FileOperation } from './installation';

// In component
const disks = detectDisks();
const tpm2Available = hasTPM2();

// During installation
const result = await runInstallation(config,
  (progress) => setProgress(progress),
  (operation) => setOperations([...operations, operation])
);
```

## Implementation Notes

All contracts are currently stubs (`throw new Error('Not implemented')`). Implementation should:

1. Follow the documented behavior in JSDoc comments
2. Use `execSync` from `child_process` for shell commands
3. Handle errors gracefully with meaningful messages
4. Call operation callbacks for transparency/logging
5. Use `/dev/disk/by-id/` paths for disk operations

## Testing

Each contract should be tested with:
1. Unit tests mocking `execSync` calls
2. Integration tests in VM environment
3. Edge case coverage (no disks, no TPM2, disk busy, etc.)
