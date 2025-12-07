# Research: TUI Local Installer

**Feature Branch**: `011-tui-local-installer`
**Date**: 2025-12-07
**Status**: Complete

## Research Tasks

### 1. NixOS Local Installation Mechanism

**Decision**: Use `nixos-install --flake` with generated configuration

**Rationale**:
- `nixos-install` is the standard NixOS local installation tool
- Flake-based installation aligns with Keystone's declarative infrastructure principle
- Proven approach used by nixos-anywhere (remotely) that we adapt for local use

**Alternatives Considered**:
- `nixos-generate-config` + manual `nixos-rebuild`: More steps, less automation
- Copy existing system closure: Complex, requires pre-built closures
- Imperative installation scripts: Violates declarative infrastructure principle

**Implementation Steps**:
```bash
# 1. Mount filesystems to /mnt
# 2. Generate/copy configuration to /mnt/home/{user}/nixos-config/
# 3. Run nixos-install
nixos-install \
  --root /mnt \
  --no-root-passwd \
  --flake /mnt/home/{user}/nixos-config#{hostname}
```

---

### 2. Disk Detection Approach

**Decision**: Use `lsblk -J -b` with JSON parsing via `jq` or native TypeScript

**Rationale**:
- JSON output is machine-parseable and stable across versions
- Bytes output (`-b`) allows accurate size calculations
- Provides all needed fields: name, size, model, type, children (partitions)

**Alternatives Considered**:
- `fdisk -l`: Output format varies, harder to parse reliably
- `/sys/block/` direct reading: Lower level, more complex
- `parted -l`: Good but less complete metadata

**TypeScript Implementation**:
```typescript
interface BlockDevice {
  name: string;
  size: number;      // bytes
  type: 'disk' | 'part' | 'lvm' | 'loop';
  model?: string;
  serial?: string;
  fstype?: string;
  children?: BlockDevice[];
}

function getDisks(): BlockDevice[] {
  const output = execSync('lsblk -J -b -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE', { encoding: 'utf-8' });
  const parsed = JSON.parse(output);
  return parsed.blockdevices
    .filter((dev: BlockDevice) => dev.type === 'disk')
    .filter((dev: BlockDevice) => !dev.name.startsWith('loop'))
    .filter((dev: BlockDevice) => !dev.name.startsWith('ram'));
}
```

---

### 3. Encrypted vs Unencrypted Installation Paths

**Decision**: Offer user choice with encrypted (ZFS+LUKS+TPM2) as recommended default

**Rationale**:
- Aligns with Constitution Principle II (Security by Default)
- Users may have valid reasons for unencrypted (VMs, testing, compatibility)
- TPM2 availability varies; must handle gracefully

**Encrypted Path (using existing disko module)**:
- ZFS pool "rpool" with encrypted datasets
- LUKS credstore (100MB) containing ZFS encryption keys
- TPM2 auto-unlock when available, password fallback otherwise
- Default credstore password: "keystone" (public, TPM enrollment mandatory)

**Unencrypted Path (simple ext4)**:
- GPT with ESP (1GB vfat) + root (ext4)
- No encryption overhead
- Simpler boot process

**TPM2 Detection**:
```typescript
export function hasTPM2(): boolean {
  try {
    execSync('systemd-cryptenroll --tpm2-device=list', {
      encoding: 'utf-8',
      stdio: 'pipe',
      timeout: 5000
    });
    return true;
  } catch {
    return false;
  }
}
```

---

### 4. Configuration File Generation

**Decision**: Generate minimal NixOS flake with host-specific configuration

**Rationale**:
- Creates user-manageable configuration from day one
- Follows Keystone patterns for flake structure
- Enables post-install customization via `nixos-rebuild`

**Generated Structure**:
```
~/nixos-config/
├── flake.nix                    # Main flake with Keystone inputs
├── flake.lock                   # Lock file (generated)
└── hosts/
    └── {hostname}/
        ├── default.nix          # Host configuration, imports modules
        ├── disk-config.nix      # Disko configuration for this disk
        └── hardware-configuration.nix  # Auto-generated hardware config
```

**Template for flake.nix**:
```nix
{
  description = "NixOS configuration for {hostname}";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    disko.url = "github:nix-community/disko";
  };

  outputs = { self, nixpkgs, keystone, disko, ... }: {
    nixosConfigurations.{hostname} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        keystone.nixosModules.diskoSingleDiskRoot
        keystone.nixosModules.{server|client}
        ./hosts/{hostname}
      ];
    };
  };
}
```

---

### 5. Hardware Configuration Generation

**Decision**: Use `nixos-generate-config --root /mnt` then move output

**Rationale**:
- Standard NixOS tool with comprehensive hardware detection
- Detects kernel modules, filesystems, CPU features automatically
- Well-tested across diverse hardware

**Alternatives Considered**:
- Manual hardware detection: Incomplete, maintenance burden
- Minimal static config: May miss important hardware-specific settings

**Post-Generation**:
```bash
nixos-generate-config --root /mnt
# Creates /mnt/etc/nixos/hardware-configuration.nix
# Move to our host directory:
mv /mnt/etc/nixos/hardware-configuration.nix \
   /mnt/home/{user}/nixos-config/hosts/{hostname}/
```

---

### 6. ISO Package Requirements

**Decision**: Add jq, tpm2-tools, disko CLI to iso-installer.nix

**Rationale**:
- `jq`: Required for reliable lsblk JSON parsing in shell
- `tpm2-tools`: TPM2 availability detection
- `disko`: Explicit disko CLI for disk formatting

**Current Packages** (from iso-installer.nix:44-66):
```nix
parted, cryptsetup, util-linux, zfs_2_3, git, curl, wget, sbctl,
networkmanager, config.boot.kernelPackages.zfs_2_3
```

**Packages to Add**:
```nix
jq              # JSON parsing
tpm2-tools      # TPM2 detection
disko           # Disk formatting CLI (if not implicit)
```

---

### 7. User Input Validation

**Decision**: Validate hostname and username per POSIX/NixOS standards

**Hostname Validation** (RFC 1123):
- 1-63 characters
- Alphanumeric and hyphens only
- Cannot start or end with hyphen
- Case-insensitive (convert to lowercase)

**Username Validation** (POSIX):
- 1-32 characters
- Lowercase letters, digits, underscore, hyphen
- Must start with lowercase letter
- Cannot match reserved names (root, nobody, etc.)

**TypeScript Validators**:
```typescript
const HOSTNAME_REGEX = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/;
const USERNAME_REGEX = /^[a-z][a-z0-9_-]{0,31}$/;
const RESERVED_USERS = ['root', 'nobody', 'daemon', 'bin', 'sys', 'sync', 'games', 'man', 'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup', 'list', 'irc', 'gnats', 'nobody', 'systemd-network', 'systemd-resolve', 'messagebus', 'polkitd'];

function validateHostname(hostname: string): { valid: boolean; error?: string } {
  if (!hostname) return { valid: false, error: 'Hostname is required' };
  if (hostname.length > 63) return { valid: false, error: 'Hostname must be 63 characters or less' };
  if (!HOSTNAME_REGEX.test(hostname.toLowerCase())) {
    return { valid: false, error: 'Hostname must contain only letters, numbers, and hyphens' };
  }
  return { valid: true };
}

function validateUsername(username: string): { valid: boolean; error?: string } {
  if (!username) return { valid: false, error: 'Username is required' };
  if (username.length > 32) return { valid: false, error: 'Username must be 32 characters or less' };
  if (!USERNAME_REGEX.test(username)) {
    return { valid: false, error: 'Username must start with letter, contain only lowercase letters, numbers, underscore, hyphen' };
  }
  if (RESERVED_USERS.includes(username)) {
    return { valid: false, error: `Username "${username}" is reserved` };
  }
  return { valid: true };
}
```

---

### 8. Error Handling and Recovery

**Decision**: Implement checkpointed installation with recovery options

**Rationale**:
- Installation involves destructive operations
- Users need clear feedback on failures
- Recovery without full restart improves UX

**Checkpoint Strategy**:
1. **Pre-partition**: Reversible via disk refresh
2. **Post-partition, pre-format**: Partition table exists but empty
3. **Post-format, pre-install**: Filesystems ready, no data yet
4. **During install**: Most critical, log all operations
5. **Post-install, pre-config-copy**: System installed, config in RAM only
6. **Complete**: All files persisted to disk

**Error Display Pattern**:
```typescript
interface InstallationError {
  phase: 'partition' | 'format' | 'mount' | 'config' | 'install' | 'finalize';
  message: string;
  command?: string;
  suggestion: string;
  recoverable: boolean;
}

// Example error:
{
  phase: 'partition',
  message: 'Device /dev/nvme0n1 is busy',
  command: 'parted /dev/nvme0n1 mklabel gpt',
  suggestion: 'Ensure no partitions are mounted. Try: umount /dev/nvme0n1*',
  recoverable: true
}
```

---

### 9. Git Repository Cloning

**Decision**: Support HTTPS and SSH URLs with authentication handling

**Rationale**:
- HTTPS: Works without SSH keys, suitable for public repos
- SSH: Required for private repos, users may have keys configured

**Implementation**:
```typescript
function cloneRepository(url: string, destPath: string): { success: boolean; error?: string } {
  try {
    // Validate URL format
    const isSSH = url.startsWith('git@') || url.includes('ssh://');
    const isHTTPS = url.startsWith('https://');

    if (!isSSH && !isHTTPS) {
      return { success: false, error: 'URL must be HTTPS or SSH format' };
    }

    execSync(`git clone --depth 1 ${url} ${destPath}`, {
      encoding: 'utf-8',
      stdio: 'pipe',
      timeout: 120000  // 2 minute timeout
    });

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    if (message.includes('Permission denied')) {
      return { success: false, error: 'SSH key authentication failed. Check your SSH keys or use HTTPS URL.' };
    }
    if (message.includes('not found')) {
      return { success: false, error: 'Repository not found. Check the URL and your access permissions.' };
    }
    return { success: false, error: `Clone failed: ${message}` };
  }
}
```

---

### 10. File Operations Transparency

**Decision**: Log all file operations to both TUI and persistent log file

**Rationale**:
- Constitution mandates user visibility into operations
- Spec FR-009 requires path and purpose display
- Log file enables post-install debugging

**Implementation**:
```typescript
interface FileOperation {
  timestamp: Date;
  action: 'create' | 'modify' | 'delete' | 'copy';
  path: string;
  purpose: string;
}

class InstallationLogger {
  private operations: FileOperation[] = [];
  private logPath = '/tmp/keystone-install.log';

  log(operation: FileOperation): void {
    this.operations.push(operation);
    const line = `[${operation.timestamp.toISOString()}] ${operation.action.toUpperCase()} ${operation.path} - ${operation.purpose}`;
    fs.appendFileSync(this.logPath, line + '\n');
    // TUI callback to display
    this.onOperation?.(operation);
  }

  getSummary(): FileOperation[] {
    return this.operations;
  }
}
```

---

## Key Findings Summary

| Topic | Decision | Key Detail |
|-------|----------|------------|
| Installation tool | `nixos-install --flake` | Standard NixOS tool with flake support |
| Disk detection | `lsblk -J -b` | JSON output, bytes for accuracy |
| Encryption | User choice, encrypted default | ZFS+LUKS+TPM2 or plain ext4 |
| TPM2 detection | `systemd-cryptenroll --tpm2-device=list` | Most reliable method |
| Config generation | Generate flake + host directory | At `~/nixos-config/hosts/{hostname}/` |
| Hardware config | `nixos-generate-config` | Standard tool, comprehensive detection |
| Validation | RFC 1123 hostname, POSIX username | With reserved name blacklist |
| Error handling | Checkpointed phases | With actionable recovery suggestions |
| Git cloning | HTTPS and SSH support | With authentication error handling |
| Logging | TUI + persistent file | At `/tmp/keystone-install.log` |

## ISO Package Additions Required

```nix
# Add to modules/iso-installer.nix environment.systemPackages
jq              # JSON parsing for lsblk
tpm2-tools      # TPM2 detection
```

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Disk path changes between detection and use | Always use `/dev/disk/by-id/` paths |
| TPM2 detection false positive | Verify with actual enrollment test, fallback to password |
| Network failure during clone | Offer retry, suggest checking connection |
| Insufficient disk space | Check minimum 8GB before starting |
| Config not copied before reboot | Block reboot until copy confirmed |
