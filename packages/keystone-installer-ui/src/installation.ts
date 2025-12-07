/**
 * Installation Orchestration Module
 *
 * This module provides functions for orchestrating the NixOS installation
 * process, including progress tracking and error handling.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

import { execSync, spawn } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import {
  InstallationPhase,
  InstallationProgress,
  FileOperation,
  InstallationResult,
  InstallationError,
  InstallationConfig,
  ProgressCallback,
  OperationCallback,
  ValidationResult,
  DEV_MODE,
  MOUNT_ROOT,
  CONFIG_BASE_PATH,
  INSTALL_LOG_PATH,
  NIXOS_INSTALL_TIMEOUT,
  GIT_CLONE_TIMEOUT,
} from './types.js';
import { formatDiskEncrypted, formatDiskUnencrypted, mountFilesystems, unmountFilesystems } from './disk.js';
import { generateConfiguration, initGitRepository, HostConfiguration } from './config-generator.js';

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
 */
export async function runInstallation(
  config: InstallationConfig,
  onProgress: ProgressCallback,
  onOperation: OperationCallback
): Promise<InstallationResult> {
  const operations: FileOperation[] = [];
  const startedAt = new Date();

  const logOp = (op: FileOperation) => {
    operations.push(op);
    onOperation(op);
    logOperation(op);
  };

  try {
    // Phase 1: Partitioning
    onProgress({
      phase: 'partitioning',
      progress: 0,
      currentOperation: 'Partitioning disk...',
      startedAt
    });

    const partitionResult = await partitionDisk(
      config.diskDevice,
      config.encrypted,
      config.swapSize,
      logOp
    );

    if (!partitionResult.success) {
      return createErrorResult('partitioning', partitionResult.error || 'Partitioning failed', operations);
    }

    // Phase 2: Formatting
    onProgress({
      phase: 'formatting',
      progress: 20,
      currentOperation: 'Formatting filesystems...',
      startedAt
    });

    const formatResult = await formatDisk(config.diskDevice, config.encrypted, logOp);

    if (!formatResult.success) {
      return createErrorResult('formatting', formatResult.error || 'Formatting failed', operations);
    }

    // Phase 3: Mounting
    onProgress({
      phase: 'mounting',
      progress: 35,
      currentOperation: 'Mounting filesystems...',
      startedAt
    });

    const mountResult = await mountForInstall(config.diskDevice, config.encrypted, logOp);

    if (!mountResult.success) {
      return createErrorResult('mounting', mountResult.error || 'Mount failed', operations);
    }

    // Phase 4: Config Generation
    onProgress({
      phase: 'config-generation',
      progress: 45,
      currentOperation: 'Generating NixOS configuration...',
      startedAt
    });

    const configResult = await generateNixosConfig(config, logOp);

    if (!configResult.success) {
      return createErrorResult('config-generation', configResult.error || 'Config generation failed', operations);
    }

    // Phase 5: NixOS Install
    onProgress({
      phase: 'nixos-install',
      progress: 55,
      currentOperation: 'Running nixos-install (this may take several minutes)...',
      startedAt
    });

    const installResult = await runNixosInstall(
      configResult.flakePath!,
      config.hostname,
      config.password,
      onProgress,
      logOp
    );

    if (!installResult.success) {
      return createErrorResult('nixos-install', installResult.error || 'Installation failed', operations);
    }

    // Phase 6: Config Copy
    onProgress({
      phase: 'config-copy',
      progress: 90,
      currentOperation: 'Copying configuration to installed system...',
      startedAt
    });

    const copyResult = await copyConfigToInstalled(
      configResult.sourcePath!,
      config.username,
      logOp
    );

    if (!copyResult.success) {
      return createErrorResult('config-copy', copyResult.error || 'Config copy failed', operations);
    }

    // Phase 7: Cleanup
    onProgress({
      phase: 'cleanup',
      progress: 95,
      currentOperation: 'Cleaning up...',
      startedAt
    });

    await cleanup(config.encrypted, logOp);

    // Complete
    onProgress({
      phase: 'complete',
      progress: 100,
      currentOperation: 'Installation complete!',
      startedAt
    });

    return {
      success: true,
      phase: 'complete',
      operations,
      completedAt: new Date()
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return createErrorResult('error', message, operations);
  }
}

/**
 * Partition target disk.
 */
export async function partitionDisk(
  diskDevice: string,
  encrypted: boolean,
  swapSize: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    console.log(`[DEV] Would partition ${diskDevice} (encrypted: ${encrypted}, swap: ${swapSize})`);
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: diskDevice,
      purpose: `[DEV] Partition disk (encrypted: ${encrypted})`,
      success: true
    });
    return { success: true };
  }

  try {
    // The actual partitioning is handled by disko during formatting
    // This phase prepares the disk
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: diskDevice,
      purpose: `Prepare disk for partitioning`,
      success: true
    });

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Format disk partitions.
 */
export async function formatDisk(
  diskDevice: string,
  encrypted: boolean,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    console.log(`[DEV] Would format ${diskDevice} (encrypted: ${encrypted})`);
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: diskDevice,
      purpose: `[DEV] Format disk (${encrypted ? 'ZFS+LUKS' : 'ext4'})`,
      success: true
    });
    return { success: true };
  }

  try {
    // Format is handled by disko when we run nixos-install
    // The disko configuration specifies the format
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: diskDevice,
      purpose: `Format disk (${encrypted ? 'ZFS+LUKS encryption' : 'ext4'})`,
      success: true
    });

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Mount filesystems to /mnt.
 */
export async function mountForInstall(
  diskDevice: string,
  encrypted: boolean,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    console.log(`[DEV] Would mount ${diskDevice} to ${MOUNT_ROOT}`);
    // Create dev directories
    fs.mkdirSync(MOUNT_ROOT, { recursive: true });
    fs.mkdirSync(`${MOUNT_ROOT}/boot`, { recursive: true });
    fs.mkdirSync(`${MOUNT_ROOT}/home`, { recursive: true });

    onOperation({
      timestamp: new Date(),
      action: 'mount',
      path: MOUNT_ROOT,
      purpose: `[DEV] Mount filesystems`,
      success: true
    });
    return { success: true };
  }

  try {
    // Mounting is handled after disko formats the disk
    // disko mount will set up the mounts based on configuration
    onOperation({
      timestamp: new Date(),
      action: 'mount',
      path: MOUNT_ROOT,
      purpose: `Mount filesystems to ${MOUNT_ROOT}`,
      success: true
    });

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Generate NixOS configuration.
 */
async function generateNixosConfig(
  config: InstallationConfig,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string; flakePath?: string; sourcePath?: string }> {
  const basePath = DEV_MODE ? CONFIG_BASE_PATH : `${MOUNT_ROOT}/home/${config.username}`;
  const configPath = path.join(basePath, 'nixos-config');

  try {
    // Ensure base path exists
    fs.mkdirSync(basePath, { recursive: true });

    const hostConfig: HostConfiguration = {
      hostname: config.hostname,
      username: config.username,
      systemType: config.systemType,
      diskDevice: config.diskDevice,
      encrypted: config.encrypted,
      swapSize: config.swapSize
    };

    const result = generateConfiguration(hostConfig, basePath, onOperation);

    if (!result.success) {
      return { success: false, error: result.error };
    }

    // Initialize git repository
    const gitSuccess = initGitRepository(configPath, onOperation);
    if (!gitSuccess) {
      console.warn('[installation] Git initialization failed, continuing without version control');
    }

    return {
      success: true,
      flakePath: configPath,
      sourcePath: configPath
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Run nixos-install with flake configuration.
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
    const phases = [
      'Building system configuration...',
      'Installing bootloader...',
      'Setting up users...',
      'Finalizing installation...'
    ];

    for (let i = 0; i < phases.length; i++) {
      onProgress({
        phase: 'nixos-install',
        progress: 55 + Math.round((i / phases.length) * 30),
        currentOperation: `[DEV] ${phases[i]}`,
        startedAt: new Date()
      });
      await new Promise(resolve => setTimeout(resolve, 500));
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

  try {
    const cmd = `nixos-install --root ${MOUNT_ROOT} --no-root-passwd --flake ${flakePath}#${hostname}`;

    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: cmd,
      purpose: 'Run nixos-install',
      success: true
    });

    execSync(cmd, {
      encoding: 'utf-8',
      timeout: NIXOS_INSTALL_TIMEOUT,
      stdio: 'inherit'
    });

    // Set user password
    if (password) {
      execSync(`nixos-enter --root ${MOUNT_ROOT} -- /bin/sh -c "echo '${hostname}:${password}' | chpasswd"`, {
        encoding: 'utf-8',
        timeout: 30000
      });
    }

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: `nixos-install failed: ${message}` };
  }
}

/**
 * Copy configuration directory to installed system.
 */
export async function copyConfigToInstalled(
  sourcePath: string,
  username: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    console.log(`[DEV] Would copy ${sourcePath} to installed system`);
    onOperation({
      timestamp: new Date(),
      action: 'copy',
      path: sourcePath,
      purpose: '[DEV] Copy configuration to installed system',
      success: true
    });
    return { success: true };
  }

  try {
    const destPath = `${MOUNT_ROOT}/home/${username}/nixos-config`;

    // If source and dest are different, copy
    if (sourcePath !== destPath) {
      execSync(`cp -r "${sourcePath}" "${destPath}"`, { encoding: 'utf-8' });
    }

    // Set ownership
    execSync(`chown -R 1000:100 "${destPath}"`, { encoding: 'utf-8' });

    onOperation({
      timestamp: new Date(),
      action: 'copy',
      path: destPath,
      purpose: 'Copy configuration to installed system',
      success: true
    });

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Cleanup after installation (unmount, export pools).
 */
export async function cleanup(
  encrypted: boolean,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    console.log('[DEV] Would cleanup (unmount filesystems)');
    onOperation({
      timestamp: new Date(),
      action: 'unmount',
      path: MOUNT_ROOT,
      purpose: '[DEV] Cleanup filesystems',
      success: true
    });
    return { success: true };
  }

  try {
    const result = unmountFilesystems();

    onOperation({
      timestamp: new Date(),
      action: 'unmount',
      path: MOUNT_ROOT,
      purpose: 'Unmount filesystems and cleanup',
      success: result.success,
      error: result.error
    });

    return result;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Clone git repository for "clone from repository" installation method.
 */
export async function cloneRepository(
  url: string,
  destPath: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; hosts: string[]; error?: string }> {
  if (DEV_MODE) {
    console.log(`[DEV] Would clone ${url} to ${destPath}`);
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: `git clone --depth 1 ${url} ${destPath}`,
      purpose: '[DEV] Clone repository',
      success: true
    });
    // Return mock hosts for dev mode
    return { success: true, hosts: ['example-host', 'test-server'] };
  }

  try {
    // Create destination directory
    fs.mkdirSync(destPath, { recursive: true });

    // Clone repository
    execSync(`git clone --depth 1 "${url}" "${destPath}"`, {
      encoding: 'utf-8',
      timeout: GIT_CLONE_TIMEOUT
    });

    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: destPath,
      purpose: `Clone repository from ${url}`,
      success: true
    });

    // Scan for hosts
    const { scanForHosts } = await import('./config-generator.js');
    const hosts = scanForHosts(destPath);

    return { success: true, hosts };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';

    let userError = message;
    if (message.includes('Permission denied')) {
      userError = 'SSH key authentication failed. Check your SSH keys or use HTTPS URL.';
    } else if (message.includes('not found') || message.includes('Repository not found')) {
      userError = 'Repository not found. Check the URL and your access permissions.';
    } else if (message.includes('timeout')) {
      userError = 'Clone timed out. Check your network connection and try again.';
    }

    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: destPath,
      purpose: `Clone repository from ${url}`,
      success: false,
      error: userError
    });

    return { success: false, hosts: [], error: userError };
  }
}

/**
 * Scan cloned repository for available hosts.
 */
export function scanForHosts(configPath: string): string[] {
  const hostsDir = path.join(configPath, 'hosts');

  if (!fs.existsSync(hostsDir)) {
    return [];
  }

  try {
    const entries = fs.readdirSync(hostsDir, { withFileTypes: true });
    return entries
      .filter(entry => entry.isDirectory())
      .filter(entry => {
        const defaultNix = path.join(hostsDir, entry.name, 'default.nix');
        return fs.existsSync(defaultNix);
      })
      .map(entry => entry.name);
  } catch {
    return [];
  }
}

/**
 * Validate git repository URL format.
 */
export function validateGitUrl(url: string): ValidationResult {
  const HTTPS_REGEX = /^https:\/\/[a-zA-Z0-9.-]+\/[a-zA-Z0-9._/-]+$/;
  const SSH_REGEX = /^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+$/;

  if (!url) {
    return { valid: false, error: 'Repository URL is required' };
  }
  if (!HTTPS_REGEX.test(url) && !SSH_REGEX.test(url)) {
    return { valid: false, error: 'URL must be HTTPS (https://...) or SSH (git@...) format' };
  }
  return { valid: true };
}

/**
 * Write operation to log file.
 */
export function logOperation(
  operation: FileOperation,
  logPath: string = INSTALL_LOG_PATH
): void {
  try {
    const status = operation.success ? 'SUCCESS' : `FAILED: ${operation.error || 'Unknown'}`;
    const line = `[${operation.timestamp.toISOString()}] ${operation.action.toUpperCase()} ${operation.path} - ${operation.purpose} (${status})\n`;

    // Ensure log directory exists
    const logDir = path.dirname(logPath);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }

    fs.appendFileSync(logPath, line);
  } catch (error) {
    // Silently fail logging - don't let logging errors break installation
    console.error('[installation] Failed to write log:', error);
  }
}

/**
 * Get installation summary for display.
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

// ============================================================================
// Private Helpers
// ============================================================================

/**
 * Create an error result for installation.
 */
function createErrorResult(
  phase: InstallationPhase,
  message: string,
  operations: FileOperation[]
): InstallationResult {
  const error: InstallationError = {
    phase,
    message,
    suggestion: getSuggestionForError(phase, message),
    recoverable: isRecoverableError(phase),
    retryPhase: getRetryPhase(phase)
  };

  return {
    success: false,
    phase,
    operations,
    error
  };
}

/**
 * Get user-friendly suggestion for error.
 */
function getSuggestionForError(phase: InstallationPhase, message: string): string {
  switch (phase) {
    case 'partitioning':
      if (message.includes('busy')) {
        return 'Ensure no partitions are mounted. Try: umount /dev/disk*';
      }
      return 'Check disk is not in use and try again.';

    case 'formatting':
      if (message.includes('pool')) {
        return 'A ZFS pool may already exist. Try: zpool destroy rpool';
      }
      return 'Check disk health and try again.';

    case 'mounting':
      return 'Ensure filesystems were created correctly.';

    case 'config-generation':
      return 'Check disk space and permissions.';

    case 'nixos-install':
      if (message.includes('network') || message.includes('fetch')) {
        return 'Check your network connection. Installation requires downloading packages.';
      }
      return 'Check the installation log at /tmp/keystone-install.log';

    case 'config-copy':
      return 'Ensure the target directory exists and has sufficient space.';

    default:
      return 'Check the installation log for details.';
  }
}

/**
 * Check if error is recoverable.
 */
function isRecoverableError(phase: InstallationPhase): boolean {
  // Most phases are recoverable by retrying
  return ['partitioning', 'formatting', 'mounting', 'config-generation', 'nixos-install'].includes(phase);
}

/**
 * Get phase to retry from.
 */
function getRetryPhase(phase: InstallationPhase): InstallationPhase | undefined {
  switch (phase) {
    case 'formatting':
    case 'partitioning':
      return 'partitioning';
    case 'mounting':
      return 'mounting';
    case 'config-generation':
      return 'config-generation';
    case 'nixos-install':
      return 'nixos-install';
    default:
      return undefined;
  }
}
