/**
 * Installation Orchestration API Contract
 *
 * This module provides functions for orchestrating the NixOS installation
 * process, including progress tracking and error handling.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

// ============================================================================
// Types
// ============================================================================

export type InstallationPhase =
  | 'idle'
  | 'partitioning'
  | 'formatting'
  | 'mounting'
  | 'config-generation'
  | 'nixos-install'
  | 'config-copy'
  | 'cleanup'
  | 'complete'
  | 'error';

export interface InstallationProgress {
  phase: InstallationPhase;
  progress: number; // 0-100
  currentOperation: string;
  startedAt: Date;
  estimatedRemainingSeconds?: number;
}

export interface FileOperation {
  timestamp: Date;
  action: 'create' | 'modify' | 'delete' | 'copy' | 'mount' | 'unmount' | 'execute';
  path: string;
  purpose: string;
  success: boolean;
  error?: string;
}

export interface InstallationResult {
  success: boolean;
  phase: InstallationPhase;
  operations: FileOperation[];
  error?: InstallationError;
  completedAt?: Date;
}

export interface InstallationError {
  phase: InstallationPhase;
  message: string;
  command?: string;
  suggestion: string;
  recoverable: boolean;
  retryPhase?: InstallationPhase;
}

export interface InstallationConfig {
  hostname: string;
  username: string;
  password: string;
  diskDevice: string;
  encrypted: boolean;
  systemType: 'server' | 'client';
  swapSize: string;
}

export type ProgressCallback = (progress: InstallationProgress) => void;
export type OperationCallback = (operation: FileOperation) => void;

// ============================================================================
// Constants
// ============================================================================

/**
 * Dev mode flag - when true, no destructive operations are performed.
 * Enable via: DEV_MODE=1 or --dev flag
 */
export const DEV_MODE = process.env.DEV_MODE === '1' || process.argv.includes('--dev');

/** Base path for installation. In dev mode, uses /tmp to avoid touching real /mnt */
export const MOUNT_ROOT = DEV_MODE ? '/tmp/keystone-dev/mnt' : '/mnt';

/** Base path for generated config. In dev mode, uses /tmp */
export const CONFIG_BASE = DEV_MODE ? '/tmp/keystone-dev' : '/mnt';

const NIXOS_INSTALL_TIMEOUT = 600000; // 10 minutes

// ============================================================================
// Public API
// ============================================================================

/**
 * Run complete local installation process.
 *
 * @param config - Installation configuration from user input
 * @param onProgress - Callback for progress updates
 * @param onOperation - Callback for file operation logging
 * @returns Installation result
 *
 * Phases executed:
 * 1. Partitioning - Create disk partitions
 * 2. Formatting - Format filesystems (ZFS/ext4)
 * 3. Mounting - Mount to /mnt
 * 4. Config generation - Create NixOS configuration
 * 5. NixOS install - Run nixos-install
 * 6. Config copy - Copy configuration to installed system
 * 7. Cleanup - Unmount filesystems
 */
export async function runInstallation(
  config: InstallationConfig,
  onProgress: ProgressCallback,
  onOperation: OperationCallback
): Promise<InstallationResult> {
  throw new Error('Not implemented');
}

/**
 * Partition target disk.
 *
 * @param diskDevice - Target disk (by-id path)
 * @param encrypted - Whether to use encrypted layout
 * @param swapSize - Swap partition size
 * @param onOperation - Operation logging callback
 * @returns Success status
 */
export async function partitionDisk(
  diskDevice: string,
  encrypted: boolean,
  swapSize: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  throw new Error('Not implemented');
}

/**
 * Format disk partitions.
 *
 * @param diskDevice - Target disk (by-id path)
 * @param encrypted - Whether to use ZFS encryption
 * @param onOperation - Operation logging callback
 * @returns Success status
 */
export async function formatDisk(
  diskDevice: string,
  encrypted: boolean,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  throw new Error('Not implemented');
}

/**
 * Mount filesystems to /mnt.
 *
 * @param diskDevice - Target disk (by-id path)
 * @param encrypted - Whether encrypted ZFS or plain ext4
 * @param onOperation - Operation logging callback
 * @returns Success status
 */
export async function mountForInstall(
  diskDevice: string,
  encrypted: boolean,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  throw new Error('Not implemented');
}

/**
 * Run nixos-install with flake configuration.
 *
 * @param flakePath - Path to flake directory
 * @param hostname - Host configuration name
 * @param password - User password to set
 * @param onProgress - Progress callback
 * @param onOperation - Operation logging callback
 * @returns Success status
 *
 * Command executed:
 * nixos-install --root /mnt --no-root-passwd --flake {flakePath}#{hostname}
 *
 * Dev mode: Simulates installation with progress updates but does not execute.
 */
export async function runNixosInstall(
  flakePath: string,
  hostname: string,
  password: string,
  onProgress: ProgressCallback,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    // Simulate installation progress
    const phases = ['Building system', 'Installing bootloader', 'Setting up users', 'Finalizing'];
    for (let i = 0; i < phases.length; i++) {
      onProgress({
        phase: 'nixos-install',
        progress: Math.round((i / phases.length) * 100),
        currentOperation: `[DEV] ${phases[i]}...`,
        startedAt: new Date()
      });
      await new Promise(resolve => setTimeout(resolve, 500)); // Simulate work
    }
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: `nixos-install --root ${MOUNT_ROOT} --flake ${flakePath}#${hostname}`,
      purpose: '[DEV] Would run nixos-install',
      success: true
    });
    return { success: true };
  }
  throw new Error('Not implemented');
}

/**
 * Copy configuration directory to installed system.
 *
 * @param sourcePath - Source config path (in live ISO environment)
 * @param username - Target user for ownership
 * @param onOperation - Operation logging callback
 * @returns Success status
 *
 * Copies from: /tmp/nixos-config (or live environment path)
 * Copies to: /mnt/home/{username}/nixos-config
 */
export async function copyConfigToInstalled(
  sourcePath: string,
  username: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  throw new Error('Not implemented');
}

/**
 * Cleanup after installation (unmount, export pools).
 *
 * @param encrypted - Whether encrypted ZFS was used
 * @param onOperation - Operation logging callback
 * @returns Success status
 */
export async function cleanup(
  encrypted: boolean,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  throw new Error('Not implemented');
}

/**
 * Clone git repository for "clone from repository" installation method.
 *
 * @param url - Git repository URL (HTTPS or SSH)
 * @param destPath - Destination path for clone
 * @param onOperation - Operation logging callback
 * @returns Success status with available hosts
 */
export async function cloneRepository(
  url: string,
  destPath: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; hosts: string[]; error?: string }> {
  // Implementation will:
  // 1. Validate URL format
  // 2. git clone --depth 1 {url} {destPath}
  // 3. Scan for hosts in hosts/ directory
  // 4. Return list of available host configurations
  throw new Error('Not implemented');
}

/**
 * Validate git repository URL format.
 *
 * @param url - URL to validate
 * @returns Validation result
 */
export function validateGitUrl(url: string): { valid: boolean; error?: string } {
  const HTTPS_REGEX = /^https:\/\/[a-zA-Z0-9.-]+\/[a-zA-Z0-9._/-]+$/;
  const SSH_REGEX = /^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+$/;

  if (!url) {
    return { valid: false, error: 'Repository URL is required' };
  }
  if (!HTTPS_REGEX.test(url) && !SSH_REGEX.test(url)) {
    return { valid: false, error: 'URL must be HTTPS or SSH format' };
  }
  return { valid: true };
}

/**
 * Write operation to log file.
 *
 * @param operation - Operation to log
 * @param logPath - Path to log file
 */
export function logOperation(
  operation: FileOperation,
  logPath: string = '/tmp/keystone-install.log'
): void {
  // Implementation will append to log file:
  // [timestamp] ACTION path - purpose (SUCCESS|FAILED: error)
  throw new Error('Not implemented');
}

/**
 * Get installation summary for display.
 *
 * @param config - Installation configuration
 * @param operations - All file operations performed
 * @returns Summary object for TUI display
 */
export function getInstallationSummary(
  config: InstallationConfig,
  operations: FileOperation[]
): {
  hostname: string;
  username: string;
  systemType: string;
  diskDevice: string;
  encrypted: boolean;
  filesCreated: number;
  configPath: string;
} {
  return {
    hostname: config.hostname,
    username: config.username,
    systemType: config.systemType,
    diskDevice: config.diskDevice,
    encrypted: config.encrypted,
    filesCreated: operations.filter(op => op.action === 'create' && op.success).length,
    configPath: `${MOUNT_ROOT}/home/${config.username}/nixos-config`
  };
}
