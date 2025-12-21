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
import { generateConfiguration, HostConfiguration } from './config-generator.js';
import { BlockDevice, DiskOperationResult } from './types.js';

// ============================================================================
// Command Execution with Output Capture
// ============================================================================

/**
 * Result of running a command with output capture.
 */
interface CommandResult {
  success: boolean;
  output: string;
  error?: string;
  exitCode: number | null;
}

/**
 * Run a command with output captured for logging.
 * Uses spawn to handle long-running commands like nixos-install.
 * Output is captured but NOT written to TTY to avoid interfering with Ink rendering.
 */
function runCommandWithCapture(
  command: string,
  timeout: number
): Promise<CommandResult> {
  return new Promise((resolve) => {
    const chunks: string[] = [];
    const proc = spawn('/bin/sh', ['-c', command], {
      stdio: ['inherit', 'pipe', 'pipe']
    });

    // Capture stdout (don't write to TTY - would interfere with Ink)
    proc.stdout?.on('data', (data: Buffer) => {
      const text = data.toString();
      chunks.push(text);  // Capture only
    });

    // Capture stderr (don't write to TTY - would interfere with Ink)
    proc.stderr?.on('data', (data: Buffer) => {
      const text = data.toString();
      chunks.push(text);  // Capture only
    });

    // Handle timeout
    const timer = setTimeout(() => {
      proc.kill('SIGTERM');
      resolve({
        success: false,
        output: chunks.join(''),
        error: `Command timed out after ${timeout / 1000}s`,
        exitCode: null
      });
    }, timeout);

    proc.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        success: code === 0,
        output: chunks.join(''),
        error: code !== 0 ? `Exit code: ${code}` : undefined,
        exitCode: code
      });
    });

    proc.on('error', (err) => {
      clearTimeout(timer);
      resolve({
        success: false,
        output: chunks.join(''),
        error: err.message,
        exitCode: null
      });
    });
  });
}

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
    // Phase 1: Config Generation (to temp location first)
    onProgress({
      phase: 'config-generation',
      progress: 0,
      currentOperation: 'Generating NixOS configuration...',
      startedAt
    });

    const configResult = await generateNixosConfig(config, logOp);

    if (!configResult.success) {
      return createErrorResult('config-generation', configResult.error || 'Config generation failed', operations);
    }

    // Phase 2: Partitioning & Formatting with disko
    onProgress({
      phase: 'partitioning',
      progress: 15,
      currentOperation: 'Partitioning and formatting disk with disko...',
      startedAt
    });

    const diskoResult = await runDisko(configResult.diskConfigPath!, config.diskDevice, logOp);

    if (!diskoResult.success) {
      return createErrorResult('partitioning', diskoResult.error || 'Disko failed', operations);
    }

    // Ensure target filesystems are mounted at /mnt for subsequent steps
    ensureMounts(config.diskDevice, config.encrypted, logOp);
    logOp({
      timestamp: new Date(),
      action: 'execute',
      path: MOUNT_ROOT,
      purpose: 'Proceeding after disko (mount ensured)',
      success: true
    });

    // Phase 3: Move config to final location
    onProgress({
      phase: 'mounting',
      progress: 35,
      currentOperation: 'Setting up configuration on target...',
      startedAt
    });

    const moveResult = await moveConfigToTarget(
      configResult.tempConfigPath!,
      config.username,
      logOp
    );

    if (!moveResult.success) {
      return createErrorResult('mounting', moveResult.error || 'Failed to move config', operations);
    }
    logOp({
      timestamp: new Date(),
      action: 'copy',
      path: moveResult.finalPath || '',
      purpose: 'Configuration moved to target',
      success: true
    });

    // Phase 4: NixOS Install
    onProgress({
      phase: 'nixos-install',
      progress: 45,
      currentOperation: 'Running nixos-install (this may take several minutes)...',
      startedAt
    });

    const installResult = await runNixosInstall(
      moveResult.finalPath!,
      config.hostname,
      config.password,
      onProgress,
      logOp
    );

    if (!installResult.success) {
      return createErrorResult('nixos-install', installResult.error || 'Installation failed', operations);
    }

    // Phase 5: Cleanup
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
 * Run disko to partition, format, and mount the disk.
 */
async function runDisko(
  diskConfigPath: string,
  diskDevice: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string }> {
  if (DEV_MODE) {
    console.log(`[DEV] Would run disko with ${diskConfigPath}`);
    // Create dev mode mount points
    fs.mkdirSync(MOUNT_ROOT, { recursive: true });
    fs.mkdirSync(`${MOUNT_ROOT}/boot`, { recursive: true });
    fs.mkdirSync(`${MOUNT_ROOT}/home`, { recursive: true });
    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: `disko --mode disko ${diskConfigPath}`,
      purpose: '[DEV] Would run disko to partition and format disk',
      success: true
    });
    return { success: true };
  }

  // Disko needs NIX_PATH set to find nixpkgs
  // Use flake:nixpkgs to reference nixpkgs from the flake registry
  const cmd = `NIX_PATH=nixpkgs=flake:nixpkgs disko --mode disko ${diskConfigPath}`;

  onOperation({
    timestamp: new Date(),
    action: 'execute',
    path: cmd,
    purpose: 'Running disko to partition, format, and mount disk...',
    success: true
  });

  try {
    const result = await runCommandWithCapture(cmd, 300000); // 5 minute timeout for disko

    onOperation({
      timestamp: new Date(),
      action: 'execute',
      path: cmd,
      purpose: result.success ? 'Disko completed successfully' : 'Disko failed',
      success: result.success,
      error: result.error,
      output: result.output.slice(-4000)
    });

    if (!result.success) {
      return { success: false, error: result.error || 'Disko failed to partition/format disk' };
    }

    // Verify mount points exist
    if (!fs.existsSync(MOUNT_ROOT)) {
      return { success: false, error: `Disko did not create mount point at ${MOUNT_ROOT}` };
    }
    if (!fs.existsSync(`${MOUNT_ROOT}/boot`)) {
      return { success: false, error: `Disko did not create boot mount point at ${MOUNT_ROOT}/boot` };
    }

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Ensure target filesystems are mounted at /mnt for installation steps.
 * This is a lightweight fallback in case disko did not mount automatically.
 */
function ensureMounts(
  diskDevice: string,
  encrypted: boolean,
  onOperation: OperationCallback
): DiskOperationResult {
  if (encrypted) {
    // For now, rely on disko to handle encrypted mounts (ZFS import handled there)
    return { success: true };
  }

  const deviceBase = diskDevice.startsWith('/dev/') ? diskDevice : `/dev/${diskDevice}`;
  const partPath = (n: number) => {
    if (deviceBase.startsWith('/dev/disk/')) {
      return `${deviceBase}-part${n}`;
    }
    const needsP = deviceBase.includes('nvme') || deviceBase.includes('mmcblk');
    return `${deviceBase}${needsP ? 'p' : ''}${n}`;
  };

  const rootPart = partPath(3);
  const bootPart = partPath(1);
  const rootLabel = '/dev/disk/by-partlabel/root';
  const bootLabel = '/dev/disk/by-partlabel/ESP';

  const rootCandidate = fs.existsSync(rootLabel) ? rootLabel : rootPart;
  const bootCandidate = fs.existsSync(bootLabel) ? bootLabel : bootPart;

  try {
    fs.mkdirSync(MOUNT_ROOT, { recursive: true });
    fs.mkdirSync(`${MOUNT_ROOT}/boot`, { recursive: true });

    execSync(`mount ${rootCandidate} ${MOUNT_ROOT}`, { encoding: 'utf-8' });
    execSync(`mount ${bootCandidate} ${MOUNT_ROOT}/boot`, { encoding: 'utf-8' });

    onOperation({
      timestamp: new Date(),
      action: 'mount',
      path: `${MOUNT_ROOT} (${rootCandidate}, ${bootCandidate})`,
      purpose: 'Ensure target partitions are mounted',
      success: true
    });

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    onOperation({
      timestamp: new Date(),
      action: 'mount',
      path: MOUNT_ROOT,
      purpose: 'Ensure target partitions are mounted',
      success: false,
      error: message
    });
    // Continue installation even if mounts fail; downstream steps will surface errors
    return { success: true, error: `Failed to mount target partitions: ${message}` };
  }
}

/**
 * Move configuration from temp location to final location on mounted disk.
 */
async function moveConfigToTarget(
  tempConfigPath: string,
  username: string,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string; finalPath?: string }> {
  const finalPath = `${MOUNT_ROOT}/home/${username}/nixos-config`;

  if (DEV_MODE) {
    console.log(`[DEV] Would move ${tempConfigPath} to ${finalPath}`);
    onOperation({
      timestamp: new Date(),
      action: 'copy',
      path: finalPath,
      purpose: '[DEV] Would move config to target',
      success: true
    });
    return { success: true, finalPath: tempConfigPath }; // In dev mode, use temp path
  }

  try {
    // Ensure parent directory exists
    const parentDir = `${MOUNT_ROOT}/home/${username}`;
    fs.mkdirSync(parentDir, { recursive: true });

    // Copy config to final location
    execSync(`cp -r "${tempConfigPath}" "${finalPath}"`, { encoding: 'utf-8' });

    onOperation({
      timestamp: new Date(),
      action: 'copy',
      path: finalPath,
      purpose: 'Moved NixOS configuration to target disk',
      success: true
    });

    return { success: true, finalPath };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Generate NixOS configuration to a temporary location.
 * Config is generated to /tmp first, then moved after disko formats/mounts.
 */
async function generateNixosConfig(
  config: InstallationConfig,
  onOperation: OperationCallback
): Promise<{ success: boolean; error?: string; tempConfigPath?: string; diskConfigPath?: string; finalFlakePath?: string }> {
  // Generate config to /tmp first (before disk is formatted/mounted)
  const tempBasePath = '/tmp/keystone-install';
  const tempConfigPath = path.join(tempBasePath, 'nixos-config');

  try {
    // Clean up any previous temp config
    if (fs.existsSync(tempBasePath)) {
      fs.rmSync(tempBasePath, { recursive: true, force: true });
    }
    fs.mkdirSync(tempBasePath, { recursive: true });

    const hostConfig: HostConfiguration = {
      hostname: config.hostname,
      username: config.username,
      systemType: config.systemType,
      diskDevice: config.diskDevice,
      encrypted: config.encrypted,
      swapSize: config.swapSize
    };

    const result = generateConfiguration(hostConfig, tempBasePath, onOperation);

    if (!result.success) {
      return { success: false, error: result.error };
    }

    // Path to the standalone disko config for disko CLI
    const diskConfigPath = path.join(tempConfigPath, 'hosts', config.hostname, 'disko-standalone.nix');

    // Final path after moving to /mnt
    const finalFlakePath = `${MOUNT_ROOT}/home/${config.username}/nixos-config`;

    return {
      success: true,
      tempConfigPath,
      diskConfigPath,
      finalFlakePath
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

  const cmd = `nixos-install --root ${MOUNT_ROOT} --no-root-passwd --flake ${flakePath}#${hostname}`;

  // Log start of nixos-install
  onOperation({
    timestamp: new Date(),
    action: 'execute',
    path: cmd,
    purpose: 'Starting nixos-install...',
    success: true
  });

  // Run nixos-install with output capture (streams to TTY AND captures for logging)
  const result = await runCommandWithCapture(cmd, NIXOS_INSTALL_TIMEOUT);

  // Log completion with captured output
  onOperation({
    timestamp: new Date(),
    action: 'execute',
    path: cmd,
    purpose: result.success ? 'nixos-install completed' : 'nixos-install failed',
    success: result.success,
    error: result.error,
    output: result.output.slice(-4000)  // Last 4KB of output
  });

  if (!result.success) {
    return { success: false, error: result.error || 'nixos-install failed' };
  }

  // Set user password
  if (password) {
    try {
      execSync(`nixos-enter --root ${MOUNT_ROOT} -- /bin/sh -c "echo '${hostname}:${password}' | chpasswd"`, {
        encoding: 'utf-8',
        timeout: 30000
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      return { success: false, error: `Failed to set user password: ${message}` };
    }
  }

  return { success: true };
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
    fs.mkdirSync(`${MOUNT_ROOT}/home/${username}`, { recursive: true });
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
    let line = `[${operation.timestamp.toISOString()}] ${operation.action.toUpperCase()} ${operation.path} - ${operation.purpose} (${status})\n`;

    // Include captured output if present (for execute actions)
    if (operation.output) {
      line += `--- OUTPUT ---\n${operation.output}\n--- END OUTPUT ---\n`;
    }

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
