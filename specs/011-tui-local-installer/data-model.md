# Data Model: TUI Local Installer

**Feature Branch**: `011-tui-local-installer`
**Date**: 2025-12-07

## Entity Overview

This document defines the TypeScript types and data structures used throughout the TUI installer. These entities represent user inputs, detected hardware, and installation state.

---

## Core Entities

### 1. BlockDevice (Storage Device)

Represents a physical or virtual block storage device detected on the system.

```typescript
/**
 * A block storage device (disk, NVMe, etc.) detected by lsblk.
 * Used for disk selection during installation.
 */
interface BlockDevice {
  /** Device name without /dev/ prefix (e.g., "nvme0n1", "sda") */
  name: string;

  /** Stable device path for reliable addressing */
  byIdPath: string | null;

  /** Total size in bytes */
  sizeBytes: number;

  /** Human-readable size (e.g., "500 GB", "2 TB") */
  sizeHuman: string;

  /** Device type */
  type: 'disk' | 'part' | 'lvm' | 'loop' | 'raid';

  /** Manufacturer model name (e.g., "Samsung SSD 980 PRO") */
  model: string | null;

  /** Serial number for unique identification */
  serial: string | null;

  /** Current filesystem type if formatted (null if raw) */
  fstype: string | null;

  /** Mount point if currently mounted */
  mountpoint: string | null;

  /** Child partitions on this device */
  children: BlockDevice[];

  /** Whether device has existing data (partitions or filesystem) */
  hasData: boolean;

  /** Whether device is currently in use (mounted or busy) */
  inUse: boolean;
}
```

**Validation Rules**:
- `sizeBytes` must be >= 8GB (8589934592 bytes) for installation
- `byIdPath` preferred over `name` for all operations
- `inUse` devices cannot be selected without unmounting first

---

### 2. NetworkInterface

Represents a network interface detected on the system.

```typescript
/**
 * A network interface (Ethernet or WiFi) with connection status.
 * Used for network setup during installation.
 */
interface NetworkInterface {
  /** Interface name (e.g., "eth0", "wlan0", "enp0s3") */
  name: string;

  /** Interface type */
  type: 'ethernet' | 'wifi' | 'other';

  /** Whether interface has link (cable connected / WiFi associated) */
  connected: boolean;

  /** IPv4 address if connected (null otherwise) */
  ipAddress: string | null;

  /** For WiFi: currently connected SSID */
  ssid: string | null;
}
```

---

### 3. WiFiNetwork

Represents a WiFi network discovered during scanning.

```typescript
/**
 * A WiFi network discovered by nmcli scan.
 */
interface WiFiNetwork {
  /** Network SSID (name) */
  ssid: string;

  /** Signal strength (0-100) */
  signal: number;

  /** Security type */
  security: 'open' | 'wep' | 'wpa' | 'wpa2' | 'wpa3' | 'unknown';

  /** Whether network is currently connected */
  connected: boolean;
}
```

---

### 4. InstallationMethod

Represents the user's chosen installation approach.

```typescript
/**
 * Installation method selected by user.
 */
type InstallationMethod =
  | { type: 'remote'; description: 'SSH installation via nixos-anywhere from another machine' }
  | { type: 'local'; description: 'Direct installation on this machine' }
  | { type: 'clone'; repositoryUrl: string; description: 'Clone existing configuration from git repository' };
```

---

### 5. EncryptionChoice

Represents the user's disk encryption preference.

```typescript
/**
 * Disk encryption choice for local installation.
 */
interface EncryptionChoice {
  /** Whether to use encryption */
  encrypted: boolean;

  /** For encrypted: whether TPM2 is available for auto-unlock */
  tpm2Available: boolean;

  /** For encrypted without TPM2: user acknowledged password-only fallback */
  passwordFallbackAcknowledged: boolean;
}
```

---

### 6. SystemType

Represents the chosen system configuration type.

```typescript
/**
 * NixOS system type (determines which Keystone module to use).
 */
type SystemType =
  | { type: 'server'; description: 'Headless server for infrastructure services (VPN, DNS, storage)' }
  | { type: 'client'; description: 'Desktop workstation with Hyprland and graphical applications' };
```

---

### 7. UserCredentials

Represents the primary user account to be created.

```typescript
/**
 * Primary user account credentials.
 */
interface UserCredentials {
  /** Unix username (lowercase, 1-32 chars, starts with letter) */
  username: string;

  /** User password (will be hashed during installation) */
  password: string;

  /** Whether user should have sudo/wheel access */
  isAdmin: boolean;
}
```

**Validation Rules**:
- `username`: `/^[a-z][a-z0-9_-]{0,31}$/`
- `username`: Not in reserved list (root, nobody, daemon, etc.)
- `password`: Minimum 1 character (no maximum, no complexity requirements for installer simplicity)

---

### 8. HostConfiguration

Represents all configuration for a host installation.

```typescript
/**
 * Complete host configuration collected during installation flow.
 */
interface HostConfiguration {
  /** Hostname for this machine (RFC 1123 compliant) */
  hostname: string;

  /** Primary user account */
  user: UserCredentials;

  /** Selected target disk */
  disk: BlockDevice;

  /** Encryption preference */
  encryption: EncryptionChoice;

  /** System type (server or client) */
  systemType: SystemType;

  /** Network configuration at installation time */
  network: {
    interfaces: NetworkInterface[];
    primaryIp: string | null;
  };

  /** Timestamp when configuration was finalized */
  configuredAt: Date;
}
```

**Validation Rules**:
- `hostname`: `/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i`
- `hostname`: 1-63 characters
- All nested objects must pass their respective validations

---

### 9. ConfigurationDirectory

Represents the generated NixOS configuration structure.

```typescript
/**
 * Generated NixOS configuration directory structure.
 */
interface ConfigurationDirectory {
  /** Root path (e.g., "/mnt/home/user/nixos-config") */
  rootPath: string;

  /** Generated files with their content */
  files: ConfigFile[];

  /** Whether git repository was initialized */
  gitInitialized: boolean;
}

interface ConfigFile {
  /** Relative path from rootPath */
  relativePath: string;

  /** Absolute path on filesystem */
  absolutePath: string;

  /** File content */
  content: string;

  /** Human-readable description of file purpose */
  purpose: string;

  /** When file was created/modified */
  timestamp: Date;
}
```

**Expected Files**:
| Path | Purpose |
|------|---------|
| `flake.nix` | Main flake with Keystone inputs and host configuration |
| `flake.lock` | Dependency lock file (generated by nix) |
| `hosts/{hostname}/default.nix` | Host-specific configuration |
| `hosts/{hostname}/disk-config.nix` | Disko disk configuration |
| `hosts/{hostname}/hardware-configuration.nix` | Auto-generated hardware config |

---

### 10. InstallationState

Represents the current state of the installation process.

```typescript
/**
 * Installation process state machine.
 */
type InstallationPhase =
  | 'idle'
  | 'network-check'
  | 'network-setup'
  | 'method-selection'
  | 'disk-selection'
  | 'disk-confirmation'
  | 'encryption-choice'
  | 'hostname-input'
  | 'username-input'
  | 'password-input'
  | 'system-type-selection'
  | 'repository-clone'
  | 'host-selection'
  | 'config-generation'
  | 'partitioning'
  | 'formatting'
  | 'mounting'
  | 'nixos-install'
  | 'config-copy'
  | 'summary'
  | 'complete'
  | 'error';

interface InstallationState {
  /** Current phase in installation flow */
  phase: InstallationPhase;

  /** Accumulated configuration (built up across phases) */
  config: Partial<HostConfiguration>;

  /** For clone method: cloned repository path */
  clonedRepoPath: string | null;

  /** For clone method: available hosts from cloned config */
  availableHosts: string[];

  /** File operations performed during installation */
  fileOperations: FileOperation[];

  /** Current error if phase is 'error' */
  error: InstallationError | null;

  /** Progress percentage for long-running operations (0-100) */
  progress: number | null;

  /** Current operation description for progress display */
  currentOperation: string | null;
}
```

---

### 11. FileOperation

Represents a logged file system operation.

```typescript
/**
 * A file operation performed during installation (for transparency).
 */
interface FileOperation {
  /** When operation occurred */
  timestamp: Date;

  /** Type of operation */
  action: 'create' | 'modify' | 'delete' | 'copy' | 'mount' | 'unmount';

  /** Affected path */
  path: string;

  /** Human-readable explanation */
  purpose: string;

  /** Whether operation succeeded */
  success: boolean;

  /** Error message if failed */
  error?: string;
}
```

---

### 12. InstallationError

Represents an error during installation.

```typescript
/**
 * An error that occurred during installation.
 */
interface InstallationError {
  /** Phase where error occurred */
  phase: InstallationPhase;

  /** Error message */
  message: string;

  /** Shell command that failed (if applicable) */
  command?: string;

  /** Suggested user action */
  suggestion: string;

  /** Whether installation can continue from this point */
  recoverable: boolean;

  /** For recoverable errors: which phase to retry from */
  retryPhase?: InstallationPhase;
}
```

---

## State Transitions

```
                              ┌─────────────┐
                              │    idle     │
                              └──────┬──────┘
                                     │
                              ┌──────▼──────┐
                              │network-check│
                              └──────┬──────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │ (no network)         │ (has network)        │
       ┌──────▼──────┐        ┌──────▼──────┐               │
       │network-setup│        │method-select│◄──────────────┘
       └──────┬──────┘        └──────┬──────┘
              │                      │
              └──────────────────────┤
                                     │
              ┌──────────────────────┼──────────────────────┐
              │ (remote)             │ (local)              │ (clone)
       ┌──────▼──────┐        ┌──────▼──────┐        ┌──────▼──────┐
       │   DISPLAY   │        │disk-select  │        │repo-clone   │
       │   SSH CMD   │        └──────┬──────┘        └──────┬──────┘
       └─────────────┘               │                      │
                              ┌──────▼──────┐        ┌──────▼──────┐
                              │disk-confirm │        │host-select  │
                              └──────┬──────┘        └──────┬──────┘
                                     │                      │
                              ┌──────▼──────┐               │
                              │encrypt-choice│              │
                              └──────┬──────┘               │
                                     │                      │
                              ┌──────▼──────┐               │
                              │hostname-input│              │
                              └──────┬──────┘               │
                                     │                      │
                              ┌──────▼──────┐               │
                              │username-input│              │
                              └──────┬──────┘               │
                                     │                      │
                              ┌──────▼──────┐               │
                              │password-input│              │
                              └──────┬──────┘               │
                                     │                      │
                              ┌──────▼──────┐               │
                              │system-type  │               │
                              └──────┬──────┘               │
                                     │                      │
                                     └──────────┬───────────┘
                                                │
                                         ┌──────▼──────┐
                                         │config-gen   │
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │partitioning │
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │formatting   │
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │mounting     │
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │nixos-install│
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │config-copy  │
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │summary      │
                                         └──────┬──────┘
                                                │
                                         ┌──────▼──────┐
                                         │complete     │
                                         └─────────────┘
```

---

## Validation Functions

```typescript
// Hostname validation (RFC 1123)
const HOSTNAME_REGEX = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i;
const MIN_HOSTNAME_LENGTH = 1;
const MAX_HOSTNAME_LENGTH = 63;

function validateHostname(hostname: string): ValidationResult {
  if (hostname.length < MIN_HOSTNAME_LENGTH) {
    return { valid: false, error: 'Hostname is required' };
  }
  if (hostname.length > MAX_HOSTNAME_LENGTH) {
    return { valid: false, error: `Hostname must be ${MAX_HOSTNAME_LENGTH} characters or less` };
  }
  if (!HOSTNAME_REGEX.test(hostname)) {
    return { valid: false, error: 'Hostname must contain only letters, numbers, and hyphens, and cannot start/end with hyphen' };
  }
  return { valid: true };
}

// Username validation (POSIX)
const USERNAME_REGEX = /^[a-z][a-z0-9_-]{0,31}$/;
const RESERVED_USERNAMES = new Set([
  'root', 'nobody', 'daemon', 'bin', 'sys', 'sync', 'games', 'man',
  'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup', 'list',
  'irc', 'gnats', 'systemd-network', 'systemd-resolve', 'messagebus',
  'polkitd', 'sshd', 'nixbld', 'nscd'
]);

function validateUsername(username: string): ValidationResult {
  if (!username) {
    return { valid: false, error: 'Username is required' };
  }
  if (!USERNAME_REGEX.test(username)) {
    return { valid: false, error: 'Username must start with a letter and contain only lowercase letters, numbers, underscore, or hyphen' };
  }
  if (RESERVED_USERNAMES.has(username)) {
    return { valid: false, error: `Username "${username}" is reserved by the system` };
  }
  return { valid: true };
}

// Disk validation
const MIN_DISK_SIZE_BYTES = 8 * 1024 * 1024 * 1024; // 8GB

function validateDiskSelection(disk: BlockDevice): ValidationResult {
  if (disk.sizeBytes < MIN_DISK_SIZE_BYTES) {
    return { valid: false, error: `Disk must be at least 8GB. Selected disk is ${disk.sizeHuman}` };
  }
  if (disk.inUse) {
    return { valid: false, error: 'Disk is currently in use. Unmount all partitions first.' };
  }
  return { valid: true };
}

// Git URL validation
const HTTPS_URL_REGEX = /^https:\/\/[a-zA-Z0-9.-]+\/[a-zA-Z0-9._/-]+$/;
const SSH_URL_REGEX = /^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+$/;

function validateGitUrl(url: string): ValidationResult {
  if (!url) {
    return { valid: false, error: 'Repository URL is required' };
  }
  if (!HTTPS_URL_REGEX.test(url) && !SSH_URL_REGEX.test(url)) {
    return { valid: false, error: 'URL must be HTTPS (https://...) or SSH (git@...) format' };
  }
  return { valid: true };
}

interface ValidationResult {
  valid: boolean;
  error?: string;
}
```

---

## Constants

```typescript
// Paths
const MOUNT_ROOT = '/mnt';
const CONFIG_DIR_NAME = 'nixos-config';
const HOSTS_DIR_NAME = 'hosts';
const INSTALL_LOG_PATH = '/tmp/keystone-install.log';

// Disko
const ZFS_POOL_NAME = 'rpool';
const CREDSTORE_PASSWORD = 'keystone';
const ESP_SIZE = '1G';
const DEFAULT_SWAP_SIZE = '8G';
const CREDSTORE_SIZE = '100M';

// Timeouts (ms)
const NETWORK_CHECK_DELAY = 2000;
const WIFI_CONNECT_TIMEOUT = 30000;
const GIT_CLONE_TIMEOUT = 120000;
const NIXOS_INSTALL_TIMEOUT = 600000; // 10 minutes

// NixOS version
const NIXOS_VERSION = '25.05';
const STATE_VERSION = '25.05';
```
