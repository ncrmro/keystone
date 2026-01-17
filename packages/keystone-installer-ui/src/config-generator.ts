/**
 * Configuration Generator Module
 *
 * This module provides functions for generating NixOS flake configurations
 * during the local installation process.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import {
  ConfigFile,
  GenerationResult,
  ValidationResult,
  SystemType,
  FileOperation,
  OperationCallback,
  DEV_MODE,
  CONFIG_BASE_PATH,
  MOUNT_ROOT,
  NIXOS_VERSION,
  STATE_VERSION,
} from './types.js';

// ============================================================================
// Types
// ============================================================================

export interface HostConfiguration {
  hostname: string;
  username: string;
  systemType: SystemType;
  diskDevice: string; // by-id path
  encrypted: boolean;
  swapSize: string;
}

// ============================================================================
// Validation Constants
// ============================================================================

const HOSTNAME_REGEX = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i;
const USERNAME_REGEX = /^[a-z][a-z0-9_-]{0,31}$/;
const RESERVED_USERNAMES = new Set([
  'root', 'nobody', 'daemon', 'bin', 'sys', 'sync', 'games', 'man',
  'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup', 'list',
  'irc', 'gnats', 'systemd-network', 'systemd-resolve', 'messagebus',
  'polkitd', 'sshd', 'nixbld', 'nscd'
]);

// ============================================================================
// Public API - Validation
// ============================================================================

/**
 * Validate hostname format per RFC 1123.
 *
 * @param hostname - Hostname to validate
 * @returns Validation result
 */
export function validateHostname(hostname: string): ValidationResult {
  if (!hostname) {
    return { valid: false, error: 'Hostname is required' };
  }
  if (hostname.length > 63) {
    return { valid: false, error: 'Hostname must be 63 characters or less' };
  }
  if (!HOSTNAME_REGEX.test(hostname)) {
    return { valid: false, error: 'Hostname must contain only letters, numbers, and hyphens, and cannot start/end with hyphen' };
  }
  return { valid: true };
}

/**
 * Validate username format per POSIX standards.
 *
 * @param username - Username to validate
 * @returns Validation result
 */
export function validateUsername(username: string): ValidationResult {
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

// ============================================================================
// Public API - Configuration Generation
// ============================================================================

/**
 * Generate complete NixOS configuration directory.
 *
 * @param config - Host configuration from user input
 * @param basePath - Base path for configuration
 * @param onOperation - Optional callback for file operations
 * @returns Generation result with list of created files
 */
export function generateConfiguration(
  config: HostConfiguration,
  basePath: string,
  onOperation?: OperationCallback
): GenerationResult {
  const files: ConfigFile[] = [];

  try {
    // Create directory structure
    const configRoot = path.join(basePath, 'nixos-config');
    const hostsDir = path.join(configRoot, 'hosts', config.hostname);

    if (DEV_MODE) {
      console.log(`[DEV] Creating configuration at ${configRoot}`);
    }

    fs.mkdirSync(hostsDir, { recursive: true });

    // Generate flake.nix
    const flakeContent = generateFlakeNix(config.hostname, config.systemType);
    const flakePath = path.join(configRoot, 'flake.nix');
    writeConfigFile(flakePath, flakeContent, 'Main flake with Keystone inputs', files, onOperation);

    // Generate host default.nix
    const hostDefaultContent = generateHostDefaultNix(config);
    const hostDefaultPath = path.join(hostsDir, 'default.nix');
    writeConfigFile(hostDefaultPath, hostDefaultContent, 'Host-specific configuration', files, onOperation);

    // Generate disk-config.nix (NixOS module for nixos-install)
    const diskConfigContent = config.encrypted
      ? generateDiskConfigEncrypted(config.diskDevice, config.swapSize)
      : generateDiskConfigUnencrypted(config.diskDevice, config.swapSize);
    const diskConfigPath = path.join(hostsDir, 'disk-config.nix');
    writeConfigFile(diskConfigPath, diskConfigContent, `Disko configuration (${config.encrypted ? 'encrypted ZFS' : 'unencrypted ext4'})`, files, onOperation);

    // Generate standalone disko config (for disko CLI)
    const standaloneDiskConfig = generateStandaloneDiskConfig(config.diskDevice, config.swapSize);
    const standaloneDiskConfigPath = path.join(hostsDir, 'disko-standalone.nix');
    writeConfigFile(standaloneDiskConfigPath, standaloneDiskConfig, 'Standalone disko config for CLI', files, onOperation);

    // Generate hardware-configuration.nix
    const hardwareContent = generateHardwareConfig();
    const hardwarePath = path.join(hostsDir, 'hardware-configuration.nix');
    writeConfigFile(hardwarePath, hardwareContent, 'Auto-generated hardware configuration', files, onOperation);

    return { success: true, files };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return { success: false, files, error: `Configuration generation failed: ${message}` };
  }
}

/**
 * Generate flake.nix content.
 *
 * @param hostname - Host name for the configuration
 * @param systemType - 'server' or 'client' module selection
 * @returns Nix file content as string
 */
export function generateFlakeNix(
  hostname: string,
  systemType: SystemType
): string {
  // For client systems, include both operating-system and desktop modules
  // For server systems, include only operating-system module
  const modules = systemType === 'client'
    ? ['keystone.nixosModules.operating-system', 'keystone.nixosModules.desktop']
    : ['keystone.nixosModules.operating-system'];

  const modulesStr = modules.join('\n        ');

  return `{
  description = "NixOS configuration for ${hostname}";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-${NIXOS_VERSION}";
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-${NIXOS_VERSION}";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        ${modulesStr}
        ./hosts/${hostname}
      ];
    };
  };
}
`;
}

/**
 * Generate host default.nix content.
 *
 * @param config - Host configuration
 * @returns Nix file content as string
 */
export function generateHostDefaultNix(config: HostConfiguration): string {
  // Generate a deterministic host ID from hostname
  const hostId = generateHostId(config.hostname);

  // Generate user configuration based on system type
  const userConfig = config.systemType === 'client'
    ? `  # Primary user with desktop environment
  keystone.os.users.${config.username} = {
    fullName = "${config.username}";
    email = "${config.username}@${config.hostname}.local";
    extraGroups = [ "wheel" "networkmanager" ];
    # Password will be set during installation
    terminal.enable = true;
    desktop = {
      enable = true;
      hyprland.enable = true;
    };
  };`
    : `  # Primary user for server
  keystone.os.users.${config.username} = {
    fullName = "${config.username}";
    email = "${config.username}@${config.hostname}.local";
    extraGroups = [ "wheel" ];
    # Password will be set during installation
    terminal.enable = true;
  };`;

  return `{ config, pkgs, lib, ... }:

{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "${config.hostname}";

  # Host ID for ZFS (required, deterministically generated from hostname)
  networking.hostId = "${hostId}";

${userConfig}

  # System state version
  system.stateVersion = "${STATE_VERSION}";
}
`;
}

/**
 * Generate disk-config.nix content for encrypted installation.
 *
 * @param diskDevice - Device path (by-id preferred)
 * @param swapSize - Swap partition size
 * @returns Nix file content as string
 */
export function generateDiskConfigEncrypted(
  diskDevice: string,
  swapSize: string
): string {
  return `{ config, ... }:

{
  # Storage configuration for encrypted ZFS installation
  # Device: ${diskDevice}

  keystone.os = {
    enable = true;
    storage = {
      type = "zfs";
      devices = [ "${diskDevice}" ];
      swap.size = "${swapSize}";
    };
  };
}
`;
}

/**
 * Generate disk-config.nix content for unencrypted installation (NixOS module format).
 *
 * @param diskDevice - Device path (by-id preferred)
 * @param swapSize - Swap partition size
 * @returns Nix file content as string
 */
export function generateDiskConfigUnencrypted(
  diskDevice: string,
  swapSize: string
): string {
  return `{ config, lib, ... }:

{
  # Storage configuration for unencrypted ext4 installation
  # Device: ${diskDevice}

  keystone.os = {
    enable = true;
    storage = {
      type = "ext4";
      devices = [ "${diskDevice}" ];
      swap.size = "${swapSize}";
    };
  };
}
`;
}

/**
 * Generate standalone disko config for disko CLI (not a NixOS module).
 * This is used by `disko --mode disko` to partition/format/mount.
 *
 * @param diskDevice - Device path (by-id preferred)
 * @param swapSize - Swap partition size
 * @returns Nix file content as string
 */
export function generateStandaloneDiskConfig(
  diskDevice: string,
  swapSize: string
): string {
  return `# Standalone disko configuration for disko CLI
# Device: ${diskDevice}
{
  disko.devices = {
    disk.root = {
      type = "disk";
      device = "${diskDevice}";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            name = "ESP";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          swap = {
            size = "${swapSize}";
            content = {
              type = "swap";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
`;
}

/**
 * Run nixos-generate-config and return hardware-configuration.nix content.
 *
 * @param rootPath - Mount point for installed system (default: "/mnt")
 * @returns Hardware configuration content
 */
export function generateHardwareConfig(rootPath: string = MOUNT_ROOT): string {
  if (DEV_MODE) {
    console.log(`[DEV] Would run: nixos-generate-config --root ${rootPath}`);
    // Return a minimal hardware config for dev mode
    return `# Auto-generated hardware configuration (DEV MODE PLACEHOLDER)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Placeholder - actual hardware config will be generated during real installation
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
`;
  }

  try {
    // Ensure the target directory exists
    const nixosDir = path.join(rootPath, 'etc', 'nixos');
    fs.mkdirSync(nixosDir, { recursive: true });

    // Run nixos-generate-config
    execSync(`nixos-generate-config --root ${rootPath}`, {
      encoding: 'utf-8',
      timeout: 30000
    });

    // Read the generated hardware configuration
    const hardwareConfigPath = path.join(nixosDir, 'hardware-configuration.nix');
    const content = fs.readFileSync(hardwareConfigPath, 'utf-8');

    return content;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error(`[config-generator] Error generating hardware config: ${message}`);

    // Return a fallback minimal config
    return `# Hardware configuration generation failed
# Error: ${message}
# Please run 'nixos-generate-config' manually after installation

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
`;
  }
}

// TODO: Git repository initialization removed from installer
// Git init during install causes ownership errors because:
// - Installer runs as root, creates .git owned by root
// - nixos-install uses Nix daemon which runs as nixbld user
// - Git refuses to operate on root-owned .git directories
// User should run `git init` after first boot as their own user

/**
 * Scan a directory for available host configurations.
 *
 * @param configPath - Path to configuration directory
 * @returns List of host names found
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
        // Check if directory contains a default.nix
        const defaultNix = path.join(hostsDir, entry.name, 'default.nix');
        return fs.existsSync(defaultNix);
      })
      .map(entry => entry.name);
  } catch (error) {
    console.error(`[config-generator] Error scanning hosts: ${error}`);
    return [];
  }
}

// ============================================================================
// Private Helpers
// ============================================================================

/**
 * Write a configuration file and track the operation.
 */
function writeConfigFile(
  filePath: string,
  content: string,
  purpose: string,
  files: ConfigFile[],
  onOperation?: OperationCallback
): void {
  const timestamp = new Date();

  try {
    fs.writeFileSync(filePath, content, 'utf-8');

    files.push({
      relativePath: path.basename(filePath),
      absolutePath: filePath,
      content,
      purpose,
      timestamp
    });

    logOp(onOperation, {
      timestamp,
      action: 'create',
      path: filePath,
      purpose,
      success: true
    });

    if (DEV_MODE) {
      console.log(`[DEV] Created: ${filePath}`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';

    logOp(onOperation, {
      timestamp,
      action: 'create',
      path: filePath,
      purpose,
      success: false,
      error: message
    });

    throw error;
  }
}

/**
 * Generate a deterministic 8-character host ID from hostname.
 */
function generateHostId(hostname: string): string {
  // Simple hash function to generate deterministic ID
  let hash = 0;
  for (let i = 0; i < hostname.length; i++) {
    const char = hostname.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  // Convert to hex and take 8 characters
  return Math.abs(hash).toString(16).padStart(8, '0').slice(0, 8);
}

/**
 * Log operation if callback is provided.
 */
function logOp(callback: OperationCallback | undefined, op: FileOperation): void {
  if (callback) {
    callback(op);
  }
}
