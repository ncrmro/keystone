# Quickstart: TUI Local Installer Development

**Feature Branch**: `011-tui-local-installer`
**Date**: 2025-12-07

## Prerequisites

- NixOS development environment with flakes enabled
- libvirt/QEMU for VM testing
- Node.js (provided by nix shell)

## Development Setup

### 1. Enter Development Shell

```bash
cd /home/ncrmro/code/ncrmro/keystone
nix develop
```

### 2. Install TUI Dependencies

```bash
cd packages/keystone-installer-ui
npm install
```

### 3. Build TUI

```bash
npm run build
# Output: dist/index.js
```

## Testing Workflow

### Dev Mode (Fastest - No VM Required)

For rapid iteration on TUI without booting a VM, run in dev mode on your host NixOS:

```bash
cd packages/keystone-installer-ui

# Build and run in dev mode
npm run build
node dist/index.js --dev
# OR set environment variable
DEV_MODE=1 node dist/index.js
```

**Dev mode behavior**:
- **Disk detection**: Shows real disks from `lsblk` but marks all as read-only
- **Disk operations**: Logs what would happen but doesn't partition/format
- **Config generation**: Writes to `/tmp/keystone-dev/nixos-config/` instead of `/mnt`
- **Installation**: Skips `nixos-install`, just shows progress simulation
- **Network**: Uses real network detection (safe, read-only)

**Implementation** (add to each module):

```typescript
// In disk.ts, config-generator.ts, installation.ts
export const DEV_MODE = process.env.DEV_MODE === '1' || process.argv.includes('--dev');

// Example in formatDiskEncrypted()
export function formatDiskEncrypted(disk: BlockDevice, swapSize: string): DiskOperationResult {
  if (DEV_MODE) {
    console.log(`[DEV] Would format ${disk.byIdPath} with ZFS+LUKS (swap: ${swapSize})`);
    return { success: true };
  }
  // Real implementation...
}

// Example config path
export const CONFIG_BASE_PATH = DEV_MODE ? '/tmp/keystone-dev' : '/mnt';
```

**What you can test in dev mode**:
- Full UI flow navigation (all screens)
- Disk selection UI (sees real disks, can't modify)
- Input validation (hostname, username, password)
- Config file generation (inspect output in /tmp/keystone-dev/)
- Error handling and recovery flows
- Progress display and file operation logging

**What requires VM testing**:
- Actual disk partitioning and formatting
- Real `nixos-install` execution
- Boot and post-install verification
- TPM2 enrollment (requires VM with swtpm)

### Quick TUI Testing (No Full ISO)

For rapid iteration on TUI code, use the terminal VM:

```bash
# Build and connect to terminal VM
./bin/build-vm terminal

# Inside VM, manually run the installer
/nix/store/.../bin/keystone-installer
```

### Full ISO Testing

For complete installation flow testing:

```bash
# 1. Build ISO with your changes
./bin/build-iso

# 2. Create and start VM
./bin/virtual-machine --name test-installer --start

# 3. Connect via serial console
virsh console test-installer

# 4. Or connect via graphical display
remote-viewer $(virsh domdisplay test-installer)

# 5. After testing, reset VM
./bin/virtual-machine --reset test-installer
```

### SSH Testing (After Network Setup)

```bash
./bin/test-vm-ssh
# or
ssh -p 2222 root@localhost  # for build-vm
ssh root@192.168.100.99     # for virtual-machine
```

## Implementation Tasks

### Task 1: Add New Screen Types

In `packages/keystone-installer-ui/src/App.tsx`:

```typescript
// Add to Screen type union
type Screen =
  | 'checking'
  | 'ethernet-connected'
  // ... existing screens ...
  | 'method-selection'      // NEW
  | 'disk-selection'        // NEW
  | 'disk-confirmation'     // NEW
  | 'encryption-choice'     // NEW
  | 'hostname-input'        // NEW
  | 'username-input'        // NEW
  | 'password-input'        // NEW
  | 'system-type-selection' // NEW
  | 'installing'            // NEW
  | 'complete'              // NEW
  | 'error';                // NEW
```

### Task 2: Create disk.ts Module

```bash
touch packages/keystone-installer-ui/src/disk.ts
```

Implement functions from `contracts/disk-operations.ts`:
- `detectDisks()` - Parse `lsblk -J -b` output
- `hasTPM2()` - Check `systemd-cryptenroll --tpm2-device=list`
- `formatDiskSize()` - Convert bytes to human-readable

### Task 3: Create config-generator.ts Module

```bash
touch packages/keystone-installer-ui/src/config-generator.ts
```

Implement functions from `contracts/config-generator.ts`:
- `generateFlakeNix()` - Template flake.nix content
- `generateHostDefaultNix()` - Template host config
- `validateHostname()` / `validateUsername()` - Input validation

### Task 4: Create installation.ts Module

```bash
touch packages/keystone-installer-ui/src/installation.ts
```

Implement functions from `contracts/installation.ts`:
- `runInstallation()` - Orchestrate full installation
- `logOperation()` - Write to /tmp/keystone-install.log

### Task 5: Update iso-installer.nix

Add required packages for local installation:

```nix
# In modules/iso-installer.nix
environment.systemPackages = with pkgs; [
  # ... existing packages ...
  jq           # JSON parsing for lsblk
  tpm2-tools   # TPM2 detection
];
```

## Key Files to Modify

| File | Changes |
|------|---------|
| `packages/keystone-installer-ui/src/App.tsx` | Add new screens, state management |
| `packages/keystone-installer-ui/src/disk.ts` | NEW: Disk operations |
| `packages/keystone-installer-ui/src/config-generator.ts` | NEW: Config generation |
| `packages/keystone-installer-ui/src/installation.ts` | NEW: Installation orchestration |
| `packages/keystone-installer-ui/package.json` | Add dependencies if needed |
| `modules/iso-installer.nix` | Add jq, tpm2-tools packages |
| `docs/installer-tui.md` | Update documentation |

## Debugging Tips

### View Installation Logs

```bash
# Inside live ISO or installed system
cat /tmp/keystone-install.log
```

### Test Disk Detection

```bash
# In live ISO environment
lsblk -J -b -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE,MOUNTPOINT | jq .
```

### Test TPM2 Detection

```bash
# Returns 0 if TPM2 available, non-zero otherwise
systemd-cryptenroll --tpm2-device=list && echo "TPM2 available"
```

### Test Config Generation

```bash
# Generate hardware config to see what nixos-generate-config produces
mkdir -p /mnt
nixos-generate-config --root /mnt --show-hardware-config
```

## Common Issues

### "Disk is busy" Error

```bash
# Find what's using the disk
lsof /dev/nvme0n1*
# Unmount any mounted partitions
umount /dev/nvme0n1*
```

### "Pool already exists" (ZFS)

```bash
# Export existing pool
zpool export rpool
# Or force destroy (DESTRUCTIVE)
zpool destroy -f rpool
```

### nixos-install Fails

```bash
# Check if filesystems are mounted correctly
mount | grep /mnt
# Verify flake path exists
ls -la /mnt/home/*/nixos-config/
```

## Running Specific Tests

### Test Disk Detection Module

```typescript
// In Node.js REPL
import { detectDisks } from './dist/disk.js';
console.log(detectDisks());
```

### Test Validation Functions

```typescript
import { validateHostname, validateUsername } from './dist/config-generator.js';
console.log(validateHostname('my-host'));    // { valid: true }
console.log(validateHostname('-invalid'));   // { valid: false, error: '...' }
console.log(validateUsername('root'));       // { valid: false, error: 'reserved' }
```

## Next Steps After Implementation

1. Run `./bin/build-iso` to create ISO with changes
2. Test in VM using `./bin/virtual-machine`
3. Verify all user stories from spec.md
4. Update documentation in docs/installer-tui.md
5. Submit PR with test results
