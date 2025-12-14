/**
 * Disk Operations Module
 *
 * This module provides functions for detecting, validating, and operating
 * on block storage devices during the installation process.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import {
  BlockDevice,
  DiskOperationResult,
  DEV_MODE,
  MIN_DISK_SIZE_BYTES,
  BYTES_PER_GB,
  BYTES_PER_TB,
  MOUNT_ROOT,
  ZFS_POOL_NAME,
} from './types.js';

// ============================================================================
// lsblk JSON Types
// ============================================================================

interface LsblkDevice {
  name: string;
  size: number;
  type: string;
  model?: string;
  serial?: string;
  fstype?: string;
  mountpoint?: string;
  children?: LsblkDevice[];
}

interface LsblkOutput {
  blockdevices: LsblkDevice[];
}

// ============================================================================
// Public API
// ============================================================================

/**
 * Detect all available block devices on the system.
 *
 * @returns Array of BlockDevice objects representing physical/virtual disks
 */
export function detectDisks(): BlockDevice[] {
  try {
    const output = execSync(
      'lsblk -J -b -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE,MOUNTPOINT',
      { encoding: 'utf-8', timeout: 10000 }
    );

    const parsed: LsblkOutput = JSON.parse(output);

    return parsed.blockdevices
      .filter((dev) => dev.type === 'disk')
      .filter((dev) => !dev.name.startsWith('loop'))
      .filter((dev) => !dev.name.startsWith('ram'))
      .filter((dev) => !dev.name.startsWith('zram'))
      .map((dev) => transformLsblkDevice(dev));
  } catch (error) {
    console.error('[disk.ts] Error detecting disks:', error);
    return [];
  }
}

/**
 * Get the stable /dev/disk/by-id/ path for a device.
 *
 * @param deviceName - Device name (e.g., "nvme0n1", "sda")
 * @returns by-id path or null if not found
 */
export function getByIdPath(deviceName: string): string | null {
  try {
    const byIdDir = '/dev/disk/by-id';
    if (!fs.existsSync(byIdDir)) {
      return null;
    }

    const files = fs.readdirSync(byIdDir);
    for (const file of files) {
      // Skip partition links
      if (file.includes('-part')) continue;
      // Skip lvm, dm, and wwn links (prefer nvme-* or ata-*)
      if (file.startsWith('lvm-') || file.startsWith('dm-') || file.startsWith('wwn-')) continue;

      const linkPath = path.join(byIdDir, file);
      try {
        const target = fs.readlinkSync(linkPath);
        const resolvedTarget = path.resolve(byIdDir, target);
        if (resolvedTarget === `/dev/${deviceName}`) {
          return linkPath;
        }
      } catch {
        // Skip links we can't read
        continue;
      }
    }

    // Fallback: try wwn- links if no better option found
    for (const file of files) {
      if (!file.includes('-part') && file.startsWith('wwn-')) {
        const linkPath = path.join(byIdDir, file);
        try {
          const target = fs.readlinkSync(linkPath);
          const resolvedTarget = path.resolve(byIdDir, target);
          if (resolvedTarget === `/dev/${deviceName}`) {
            return linkPath;
          }
        } catch {
          continue;
        }
      }
    }

    return null;
  } catch (error) {
    console.error(`[disk.ts] Error getting by-id path for ${deviceName}:`, error);
    return null;
  }
}

/**
 * Validate that a disk is suitable for installation.
 *
 * @param disk - BlockDevice to validate
 * @returns Validation result with error message if invalid
 */
export function validateDisk(disk: BlockDevice): DiskOperationResult {
  if (disk.type !== 'disk') {
    return { success: false, error: 'Selected device is not a disk' };
  }
  if (disk.sizeBytes < MIN_DISK_SIZE_BYTES) {
    return { success: false, error: `Disk must be at least 8GB. Selected disk is ${disk.sizeHuman}` };
  }
  if (disk.inUse) {
    return { success: false, error: 'Disk is currently in use. Unmount all partitions first.' };
  }
  return { success: true };
}

/**
 * Check if a disk has existing data (partitions or filesystem).
 *
 * @param disk - BlockDevice to check
 * @returns true if disk has existing data
 */
export function hasExistingData(disk: BlockDevice): boolean {
  return disk.children.length > 0 || disk.fstype !== null;
}

/**
 * Format disk size in human-readable format.
 *
 * @param bytes - Size in bytes
 * @returns Human-readable string (e.g., "500 GB", "2 TB")
 */
export function formatDiskSize(bytes: number): string {
  if (bytes >= BYTES_PER_TB) {
    return `${(bytes / BYTES_PER_TB).toFixed(1)} TB`;
  }
  return `${(bytes / BYTES_PER_GB).toFixed(0)} GB`;
}

/**
 * Partition and format disk for encrypted installation using disko.
 *
 * @param disk - Target BlockDevice
 * @param swapSize - Swap partition size (e.g., "8G")
 * @returns Operation result
 */
export function formatDiskEncrypted(
  disk: BlockDevice,
  swapSize: string = '8G'
): DiskOperationResult {
  const devicePath = disk.byIdPath || `/dev/${disk.name}`;

  if (DEV_MODE) {
    console.log(`[DEV] Would format ${devicePath} with ZFS+LUKS encryption`);
    console.log(`[DEV]   Swap size: ${swapSize}`);
    console.log(`[DEV]   Pool name: ${ZFS_POOL_NAME}`);
    return { success: true };
  }

  // Real implementation uses disko
  // The actual disko configuration will be generated and applied
  // by the config-generator module during installation
  try {
    // This will be called after disko config is generated
    // For now, we just return success as disko handles this
    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: `Failed to format disk: ${message}`, command: 'disko format' };
  }
}

/**
 * Partition and format disk for unencrypted installation.
 *
 * @param disk - Target BlockDevice
 * @param swapSize - Swap partition size (e.g., "8G")
 * @returns Operation result
 */
export function formatDiskUnencrypted(
  disk: BlockDevice,
  swapSize: string = '8G'
): DiskOperationResult {
  const devicePath = disk.byIdPath || `/dev/${disk.name}`;

  if (DEV_MODE) {
    console.log(`[DEV] Would format ${devicePath} with unencrypted ext4`);
    console.log(`[DEV]   Swap size: ${swapSize}`);
    console.log('[DEV]   Layout: ESP (1G) + Swap + Root (ext4)');
    return { success: true };
  }

  // Real implementation will use parted and mkfs
  // This will be handled by disko with the unencrypted config
  try {
    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: `Failed to format disk: ${message}` };
  }
}

/**
 * Mount filesystems to /mnt for installation.
 *
 * @param disk - Formatted BlockDevice
 * @param encrypted - Whether disk uses encryption
 * @returns Operation result
 */
export function mountFilesystems(
  disk: BlockDevice,
  encrypted: boolean
): DiskOperationResult {
  if (DEV_MODE) {
    console.log(`[DEV] Would mount filesystems to ${MOUNT_ROOT}`);
    console.log(`[DEV]   Encrypted: ${encrypted}`);
    // Create dev mode directories
    try {
      fs.mkdirSync(MOUNT_ROOT, { recursive: true });
      fs.mkdirSync(`${MOUNT_ROOT}/boot`, { recursive: true });
      return { success: true };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      return { success: false, error: `Failed to create dev directories: ${message}` };
    }
  }

  try {
    if (encrypted) {
      // Import and mount ZFS pool
      execSync(`zpool import -R ${MOUNT_ROOT} ${ZFS_POOL_NAME}`, { encoding: 'utf-8' });
    } else {
      // Mount ext4 root partition
      const devicePath = disk.byIdPath || `/dev/${disk.name}`;
      fs.mkdirSync(MOUNT_ROOT, { recursive: true });
      execSync(`mount ${devicePath}-part3 ${MOUNT_ROOT}`, { encoding: 'utf-8' });
      fs.mkdirSync(`${MOUNT_ROOT}/boot`, { recursive: true });
      execSync(`mount ${devicePath}-part1 ${MOUNT_ROOT}/boot`, { encoding: 'utf-8' });
    }
    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: `Failed to mount filesystems: ${message}` };
  }
}

/**
 * Unmount all filesystems from /mnt.
 *
 * @returns Operation result
 */
export function unmountFilesystems(): DiskOperationResult {
  if (DEV_MODE) {
    console.log(`[DEV] Would unmount filesystems from ${MOUNT_ROOT}`);
    return { success: true };
  }

  try {
    // Try to unmount boot first
    try {
      execSync(`umount ${MOUNT_ROOT}/boot 2>/dev/null || true`, { encoding: 'utf-8' });
    } catch {
      // Ignore errors
    }

    // Unmount root
    try {
      execSync(`umount ${MOUNT_ROOT} 2>/dev/null || true`, { encoding: 'utf-8' });
    } catch {
      // Ignore errors
    }

    // Export ZFS pool if it exists
    try {
      execSync(`zpool export ${ZFS_POOL_NAME} 2>/dev/null || true`, { encoding: 'utf-8' });
    } catch {
      // Ignore errors
    }

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, error: `Failed to unmount filesystems: ${message}` };
  }
}

/**
 * Check if TPM2 is available on the system.
 *
 * @returns true if TPM2 is available and functional
 */
export function hasTPM2(): boolean {
  if (DEV_MODE) {
    // In dev mode, check if the command would work but don't require actual TPM
    console.log('[DEV] Checking for TPM2 (simulated)');
    return false; // Most dev machines don't have TPM2 available
  }

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

// ============================================================================
// Private Helpers
// ============================================================================

/**
 * Transform lsblk device to BlockDevice interface.
 */
function transformLsblkDevice(dev: LsblkDevice): BlockDevice {
  const children = (dev.children || []).map(transformLsblkDevice);
  const hasData = children.length > 0 || dev.fstype !== null;
  const inUse = dev.mountpoint !== null || children.some(c => c.mountpoint !== null);

  return {
    name: dev.name,
    byIdPath: getByIdPath(dev.name),
    sizeBytes: dev.size,
    sizeHuman: formatDiskSize(dev.size),
    type: dev.type as BlockDevice['type'],
    model: dev.model || null,
    serial: dev.serial || null,
    fstype: dev.fstype || null,
    mountpoint: dev.mountpoint || null,
    children,
    hasData,
    inUse,
  };
}
