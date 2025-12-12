/**
 * Shared Types for Keystone Installer TUI
 *
 * This module provides TypeScript types and data structures used throughout
 * the TUI installer.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

// ============================================================================
// Dev Mode Support
// ============================================================================

/**
 * Dev mode flag - when true, no destructive operations are performed.
 * Enable via: DEV_MODE=1 or --dev flag
 */
export const DEV_MODE = process.env.DEV_MODE === '1' || process.argv.includes('--dev');

/** Base path for generated config. In dev mode, uses /tmp for safe testing */
export const CONFIG_BASE_PATH = DEV_MODE ? '/tmp/keystone-dev' : '/mnt';

/** Mount root for installation */
export const MOUNT_ROOT = DEV_MODE ? '/tmp/keystone-dev/mnt' : '/mnt';

// ============================================================================
// Block Device Types
// ============================================================================

/**
 * A block storage device (disk, NVMe, etc.) detected by lsblk.
 * Used for disk selection during installation.
 */
export interface BlockDevice {
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

// ============================================================================
// Network Types
// ============================================================================

/**
 * A network interface (Ethernet or WiFi) with connection status.
 * Used for network setup during installation.
 */
export interface NetworkInterface {
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

/**
 * A WiFi network discovered by nmcli scan.
 */
export interface WiFiNetwork {
  /** Network SSID (name) */
  ssid: string;

  /** Signal strength (0-100) */
  signal: number;

  /** Security type */
  security: 'open' | 'wep' | 'wpa' | 'wpa2' | 'wpa3' | 'unknown';

  /** Whether network is currently connected */
  connected: boolean;
}

// ============================================================================
// Installation Method Types
// ============================================================================

/**
 * Installation method selected by user.
 */
export type InstallationMethod =
  | { type: 'remote'; description: string }
  | { type: 'local'; description: string }
  | { type: 'clone'; repositoryUrl: string; description: string };

// ============================================================================
// Encryption Types
// ============================================================================

/**
 * Disk encryption choice for local installation.
 */
export interface EncryptionChoice {
  /** Whether to use encryption */
  encrypted: boolean;

  /** For encrypted: whether TPM2 is available for auto-unlock */
  tpm2Available: boolean;

  /** For encrypted without TPM2: user acknowledged password-only fallback */
  passwordFallbackAcknowledged: boolean;
}

// ============================================================================
// System Type
// ============================================================================

/**
 * NixOS system type (determines which Keystone module to use).
 */
export type SystemType = 'server' | 'client';

// ============================================================================
// User Credentials
// ============================================================================

/**
 * Primary user account credentials.
 */
export interface UserCredentials {
  /** Unix username (lowercase, 1-32 chars, starts with letter) */
  username: string;

  /** User password (will be hashed during installation) */
  password: string;

  /** Whether user should have sudo/wheel access */
  isAdmin: boolean;
}

// ============================================================================
// Host Configuration
// ============================================================================

/**
 * Complete host configuration collected during installation flow.
 */
export interface HostConfiguration {
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

// ============================================================================
// Configuration Generation Types
// ============================================================================

/**
 * Generated configuration file.
 */
export interface ConfigFile {
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

/**
 * Generated NixOS configuration directory structure.
 */
export interface ConfigurationDirectory {
  /** Root path (e.g., "/mnt/home/user/nixos-config") */
  rootPath: string;

  /** Generated files with their content */
  files: ConfigFile[];

  /** Whether git repository was initialized */
  gitInitialized: boolean;
}

// ============================================================================
// Installation State Types
// ============================================================================

/**
 * Installation process state machine phases.
 */
export type InstallationPhase =
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
  | 'cleanup'
  | 'summary'
  | 'complete'
  | 'error';

/**
 * A file operation performed during installation (for transparency).
 */
export interface FileOperation {
  /** When operation occurred */
  timestamp: Date;

  /** Type of operation */
  action: 'create' | 'modify' | 'delete' | 'copy' | 'mount' | 'unmount' | 'execute';

  /** Affected path */
  path: string;

  /** Human-readable explanation */
  purpose: string;

  /** Whether operation succeeded */
  success: boolean;

  /** Error message if failed */
  error?: string;

  /** Captured command output (for execute actions) */
  output?: string;
}

/**
 * An error that occurred during installation.
 */
export interface InstallationError {
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

/**
 * Installation process state.
 */
export interface InstallationState {
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

// ============================================================================
// Installation Progress Types
// ============================================================================

/**
 * Progress information for long-running operations.
 */
export interface InstallationProgress {
  phase: InstallationPhase;
  progress: number; // 0-100
  currentOperation: string;
  startedAt: Date;
  estimatedRemainingSeconds?: number;
}

/**
 * Result of an installation operation.
 */
export interface InstallationResult {
  success: boolean;
  phase: InstallationPhase;
  operations: FileOperation[];
  error?: InstallationError;
  completedAt?: Date;
}

/**
 * Configuration for running an installation.
 */
export interface InstallationConfig {
  hostname: string;
  username: string;
  password: string;
  diskDevice: string;
  encrypted: boolean;
  systemType: SystemType;
  swapSize: string;
}

// ============================================================================
// Callback Types
// ============================================================================

export type ProgressCallback = (progress: InstallationProgress) => void;
export type OperationCallback = (operation: FileOperation) => void;

// ============================================================================
// Validation Types
// ============================================================================

/**
 * Result of a validation check.
 */
export interface ValidationResult {
  valid: boolean;
  error?: string;
}

/**
 * Result of a disk operation.
 */
export interface DiskOperationResult {
  success: boolean;
  error?: string;
  command?: string;
}

/**
 * Result of configuration generation.
 */
export interface GenerationResult {
  success: boolean;
  files: ConfigFile[];
  error?: string;
}

// ============================================================================
// Constants
// ============================================================================

// Paths
export const CONFIG_DIR_NAME = 'nixos-config';
export const HOSTS_DIR_NAME = 'hosts';
export const INSTALL_LOG_PATH = '/tmp/keystone-install.log';

// Disko
export const ZFS_POOL_NAME = 'rpool';
export const CREDSTORE_PASSWORD = 'keystone';
export const ESP_SIZE = '1G';
export const DEFAULT_SWAP_SIZE = '8G';
export const CREDSTORE_SIZE = '100M';

// Size limits
export const MIN_DISK_SIZE_BYTES = 8 * 1024 * 1024 * 1024; // 8GB
export const BYTES_PER_GB = 1024 * 1024 * 1024;
export const BYTES_PER_TB = 1024 * 1024 * 1024 * 1024;

// Timeouts (ms)
export const NETWORK_CHECK_DELAY = 2000;
export const WIFI_CONNECT_TIMEOUT = 30000;
export const GIT_CLONE_TIMEOUT = 120000;
export const NIXOS_INSTALL_TIMEOUT = 600000; // 10 minutes

// NixOS version
export const NIXOS_VERSION = '25.05';
export const STATE_VERSION = '25.05';
