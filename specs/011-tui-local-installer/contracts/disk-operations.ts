/**
 * Disk Operations API Contract
 *
 * This module provides functions for detecting, validating, and operating
 * on block storage devices during the installation process.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

import { execSync } from 'child_process';

// ============================================================================
// Types
// ============================================================================

export interface BlockDevice {
  name: string;
  byIdPath: string | null;
  sizeBytes: number;
  sizeHuman: string;
  type: 'disk' | 'part' | 'lvm' | 'loop' | 'raid';
  model: string | null;
  serial: string | null;
  fstype: string | null;
  mountpoint: string | null;
  children: BlockDevice[];
  hasData: boolean;
  inUse: boolean;
}

export interface DiskOperationResult {
  success: boolean;
  error?: string;
  command?: string;
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Dev mode flag - when true, no destructive operations are performed.
 * Enable via: DEV_MODE=1 or --dev flag
 */
export const DEV_MODE = process.env.DEV_MODE === '1' || process.argv.includes('--dev');

const MIN_DISK_SIZE_BYTES = 8 * 1024 * 1024 * 1024; // 8GB
const BYTES_PER_GB = 1024 * 1024 * 1024;
const BYTES_PER_TB = 1024 * 1024 * 1024 * 1024;

// ============================================================================
// Public API
// ============================================================================

/**
 * Detect all available block devices on the system.
 *
 * @returns Array of BlockDevice objects representing physical/virtual disks
 *
 * Implementation notes:
 * - Uses `lsblk -J -b` for reliable JSON output with byte sizes
 * - Filters out loop devices, RAM disks, and other non-installable targets
 * - Resolves by-id paths for stable device addressing
 */
export function detectDisks(): BlockDevice[] {
  // Implementation will use:
  // execSync('lsblk -J -b -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE,MOUNTPOINT', { encoding: 'utf-8' })
  throw new Error('Not implemented');
}

/**
 * Get the stable /dev/disk/by-id/ path for a device.
 *
 * @param deviceName - Device name (e.g., "nvme0n1", "sda")
 * @returns by-id path or null if not found
 *
 * Implementation notes:
 * - Reads symlinks from /dev/disk/by-id/
 * - Prefers nvme-* or ata-* paths over wwn-* paths
 */
export function getByIdPath(deviceName: string): string | null {
  // Implementation will use:
  // execSync(`readlink -f /dev/disk/by-id/* | grep -l "${deviceName}$"`, ...)
  throw new Error('Not implemented');
}

/**
 * Validate that a disk is suitable for installation.
 *
 * @param disk - BlockDevice to validate
 * @returns Validation result with error message if invalid
 *
 * Validation rules:
 * - Disk must be at least 8GB
 * - Disk must not be currently mounted
 * - Disk must be of type 'disk' (not partition, lvm, etc.)
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
 *
 * Used to show data destruction warning to user.
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
 *
 * Implementation notes:
 * - Generates temporary disko configuration
 * - Calls `disko format` with configuration
 * - Creates ZFS pool "rpool" with encrypted datasets
 * - Creates LUKS credstore for ZFS key storage
 *
 * Dev mode: Logs operation details but does not execute. Returns success.
 */
export function formatDiskEncrypted(
  disk: BlockDevice,
  swapSize: string = '8G'
): DiskOperationResult {
  if (DEV_MODE) {
    console.log(`[DEV] Would format ${disk.byIdPath || disk.name} with ZFS+LUKS encryption`);
    console.log(`[DEV]   Swap size: ${swapSize}`);
    console.log(`[DEV]   Pool name: rpool`);
    return { success: true };
  }
  // Implementation will:
  // 1. Generate disko config Nix file
  // 2. Execute: disko format --write-partition-table --write-filesystems /path/to/config.nix
  throw new Error('Not implemented');
}

/**
 * Partition and format disk for unencrypted installation.
 *
 * @param disk - Target BlockDevice
 * @param swapSize - Swap partition size (e.g., "8G")
 * @returns Operation result
 *
 * Partition layout:
 * - ESP: 1GB vfat at /boot
 * - Swap: swapSize
 * - Root: remaining space as ext4
 */
export function formatDiskUnencrypted(
  disk: BlockDevice,
  swapSize: string = '8G'
): DiskOperationResult {
  // Implementation will:
  // 1. parted ${device} mklabel gpt
  // 2. parted ${device} mkpart ESP fat32 1MiB 1GiB
  // 3. parted ${device} mkpart swap linux-swap 1GiB ${1 + swapGB}GiB
  // 4. parted ${device} mkpart root ext4 ${1 + swapGB}GiB 100%
  // 5. mkfs.vfat ${device}-part1
  // 6. mkswap ${device}-part2
  // 7. mkfs.ext4 ${device}-part3
  throw new Error('Not implemented');
}

/**
 * Mount filesystems to /mnt for installation.
 *
 * @param disk - Formatted BlockDevice
 * @param encrypted - Whether disk uses encryption
 * @returns Operation result
 *
 * For encrypted:
 * - Import ZFS pool to /mnt
 * - Mount encrypted datasets
 * - Mount ESP to /mnt/boot
 *
 * For unencrypted:
 * - Mount ext4 root to /mnt
 * - Mount ESP to /mnt/boot
 */
export function mountFilesystems(
  disk: BlockDevice,
  encrypted: boolean
): DiskOperationResult {
  throw new Error('Not implemented');
}

/**
 * Unmount all filesystems from /mnt.
 *
 * @returns Operation result
 *
 * Order:
 * 1. Unmount /mnt/boot
 * 2. Unmount /mnt (and ZFS datasets if encrypted)
 * 3. Export ZFS pool if encrypted
 */
export function unmountFilesystems(): DiskOperationResult {
  throw new Error('Not implemented');
}

/**
 * Check if TPM2 is available on the system.
 *
 * @returns true if TPM2 is available and functional
 *
 * Detection method:
 * - Uses systemd-cryptenroll --tpm2-device=list
 * - Returns false if command fails or no devices found
 */
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
