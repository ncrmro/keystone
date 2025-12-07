/**
 * Configuration Generator API Contract
 *
 * This module provides functions for generating NixOS flake configurations
 * during the local installation process.
 *
 * Feature: 011-tui-local-installer
 * Date: 2025-12-07
 */

// ============================================================================
// Types
// ============================================================================

export interface HostConfiguration {
  hostname: string;
  username: string;
  systemType: 'server' | 'client';
  diskDevice: string; // by-id path
  encrypted: boolean;
  swapSize: string;
}

export interface ConfigFile {
  relativePath: string;
  absolutePath: string;
  content: string;
  purpose: string;
}

export interface GenerationResult {
  success: boolean;
  files: ConfigFile[];
  error?: string;
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Dev mode flag - when true, writes to /tmp instead of /mnt.
 * Enable via: DEV_MODE=1 or --dev flag
 */
export const DEV_MODE = process.env.DEV_MODE === '1' || process.argv.includes('--dev');

/** Base path for generated config. In dev mode, uses /tmp for safe testing */
export const CONFIG_BASE_PATH = DEV_MODE ? '/tmp/keystone-dev' : '/mnt';

const NIXOS_VERSION = '25.05';
const STATE_VERSION = '25.05';
const ZFS_POOL_NAME = 'rpool';

// ============================================================================
// Public API
// ============================================================================

/**
 * Generate complete NixOS configuration directory.
 *
 * @param config - Host configuration from user input
 * @param basePath - Base path for configuration (e.g., "/mnt/home/user/nixos-config")
 * @returns Generation result with list of created files
 *
 * Generated structure:
 * - flake.nix - Main flake with Keystone inputs
 * - hosts/{hostname}/default.nix - Host configuration
 * - hosts/{hostname}/disk-config.nix - Disko configuration
 * - hosts/{hostname}/hardware-configuration.nix - Hardware detection
 */
export function generateConfiguration(
  config: HostConfiguration,
  basePath: string
): GenerationResult {
  throw new Error('Not implemented');
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
  systemType: 'server' | 'client'
): string {
  return `{
  description = "NixOS configuration for ${hostname}";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-${NIXOS_VERSION}";
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, keystone, disko, ... }: {
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        keystone.nixosModules.diskoSingleDiskRoot
        keystone.nixosModules.${systemType}
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
  return `{ config, pkgs, lib, ... }:

{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "${config.hostname}";

  # Host ID for ZFS (required)
  networking.hostId = "$(head -c 8 /etc/machine-id)";

  # Primary user
  users.users.${config.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # Password will be set during nixos-install
  };

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
  # Disko configuration for encrypted ZFS installation
  # Device: ${diskDevice}

  keystone.disko = {
    enable = true;
    device = "${diskDevice}";
    swapSize = "${swapSize}";
  };
}
`;
}

/**
 * Generate disk-config.nix content for unencrypted installation.
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
  # Simple disk configuration for unencrypted installation
  # Device: ${diskDevice}

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

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
`;
}

/**
 * Run nixos-generate-config and return hardware-configuration.nix content.
 *
 * @param rootPath - Mount point for installed system (default: "/mnt")
 * @returns Hardware configuration content
 *
 * Implementation notes:
 * - Runs: nixos-generate-config --root /mnt
 * - Reads: /mnt/etc/nixos/hardware-configuration.nix
 * - Strips auto-generated comments for cleaner output
 */
export function generateHardwareConfig(rootPath: string = '/mnt'): string {
  // Implementation will:
  // execSync(`nixos-generate-config --root ${rootPath}`, ...)
  // return fs.readFileSync(`${rootPath}/etc/nixos/hardware-configuration.nix`, 'utf-8')
  throw new Error('Not implemented');
}

/**
 * Initialize git repository in configuration directory.
 *
 * @param configPath - Path to configuration directory
 * @returns Success status
 */
export function initGitRepository(configPath: string): boolean {
  // Implementation will:
  // execSync(`git init ${configPath}`, ...)
  // execSync(`git -C ${configPath} add -A`, ...)
  // execSync(`git -C ${configPath} commit -m "Initial configuration"`, ...)
  throw new Error('Not implemented');
}

/**
 * Validate hostname format per RFC 1123.
 *
 * @param hostname - Hostname to validate
 * @returns Validation result
 */
export function validateHostname(hostname: string): { valid: boolean; error?: string } {
  const HOSTNAME_REGEX = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i;

  if (!hostname) {
    return { valid: false, error: 'Hostname is required' };
  }
  if (hostname.length > 63) {
    return { valid: false, error: 'Hostname must be 63 characters or less' };
  }
  if (!HOSTNAME_REGEX.test(hostname)) {
    return { valid: false, error: 'Hostname must contain only letters, numbers, and hyphens' };
  }
  return { valid: true };
}

/**
 * Validate username format per POSIX standards.
 *
 * @param username - Username to validate
 * @returns Validation result
 */
export function validateUsername(username: string): { valid: boolean; error?: string } {
  const USERNAME_REGEX = /^[a-z][a-z0-9_-]{0,31}$/;
  const RESERVED = new Set([
    'root', 'nobody', 'daemon', 'bin', 'sys', 'sync', 'games', 'man',
    'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup', 'list',
    'irc', 'gnats', 'systemd-network', 'systemd-resolve', 'messagebus',
    'polkitd', 'sshd', 'nixbld', 'nscd'
  ]);

  if (!username) {
    return { valid: false, error: 'Username is required' };
  }
  if (!USERNAME_REGEX.test(username)) {
    return { valid: false, error: 'Username must start with a letter and contain only lowercase letters, numbers, underscore, or hyphen' };
  }
  if (RESERVED.has(username)) {
    return { valid: false, error: `Username "${username}" is reserved` };
  }
  return { valid: true };
}
