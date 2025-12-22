# Keystone OS - Shared Option Definitions
#
# This module defines all keystone.os.* options that are shared across platforms.
# Platform-specific modules (x86, mac) implement these options differently.
#
{
  lib,
  ...
}:
with lib; let
  # User submodule type definition
  userSubmodule = types.submodule ({name, ...}: {
    options = {
      uid = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "User ID. If null, NixOS will auto-assign.";
      };

      fullName = mkOption {
        type = types.str;
        description = "Full name of the user (used for GECOS and git config)";
        example = "Alice Smith";
      };

      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Email address (used for git config)";
        example = "alice@example.com";
      };

      extraGroups = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Additional groups the user should be a member of";
        example = ["wheel" "networkmanager"];
      };

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "SSH public keys for the user. Also used for remote unlock if enabled.";
        example = ["ssh-ed25519 AAAAC3... alice@laptop"];
      };

      initialPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Initial plaintext password. WARNING: Stored in Nix store. Use hashedPassword for production.";
      };

      hashedPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Hashed password (generate with mkpasswd -m sha-512)";
      };

      terminal = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable terminal development environment (zsh, helix, zellij, starship, git)";
        };
      };

      desktop = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable desktop environment (Hyprland, waybar, etc.)";
        };

        hyprland = {
          modifierKey = mkOption {
            type = types.enum ["SUPER" "ALT"];
            default = "SUPER";
            description = "Primary modifier key for Hyprland keybindings";
          };

          capslockAsControl = mkOption {
            type = types.bool;
            default = true;
            description = "Remap Caps Lock to Control";
          };
        };
      };

      zfs = {
        quota = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "ZFS quota for user's home dataset (e.g., '100G', '1T')";
          example = "100G";
        };

        compression = mkOption {
          type = types.enum ["off" "on" "lz4" "gzip" "zstd" "zstd-fast" "lzjb"];
          default = "lz4";
          description = "Compression algorithm for user's home dataset";
        };

        recordsize = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Block size for the dataset (128K default, 1M for large files, 16K for databases)";
        };

        atime = mkOption {
          type = types.enum ["on" "off"];
          default = "off";
          description = "Whether to update access time on file reads";
        };
      };
    };
  });
in {
  options.keystone.os = {
    enable = mkEnableOption "Keystone OS - secure storage, boot, and user management";

    # Storage configuration
    storage = {
      type = mkOption {
        type = types.enum ["zfs" "ext4"];
        default = "zfs";
        description = ''
          Filesystem type for the root pool.
          - zfs: Full features (snapshots, compression, checksums, native encryption)
          - ext4: Simple/legacy (LUKS encryption only, no advanced features)
        '';
      };

      devices = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB"];
        description = ''
          Disk devices for the storage pool. Use by-id paths for stability.
          For multi-disk configurations, specify multiple devices and set mode.
        '';
      };

      mode = mkOption {
        type = types.enum ["single" "mirror" "stripe" "raidz1" "raidz2" "raidz3"];
        default = "single";
        description = ''
          Redundancy mode for multi-disk ZFS configurations:
          - single: No redundancy (single disk or concatenated)
          - mirror: All disks mirror each other (RAID1)
          - stripe: Data striped across disks (RAID0, no redundancy)
          - raidz1: Single parity (RAID5 equivalent, min 3 disks)
          - raidz2: Double parity (RAID6 equivalent, min 4 disks)
          - raidz3: Triple parity (min 5 disks)
        '';
      };

      esp = {
        size = mkOption {
          type = types.str;
          default = "1G";
          description = "EFI System Partition size";
        };
      };

      swap = {
        size = mkOption {
          type = types.str;
          default = "8G";
          description = "Swap partition size. Set to '0' to disable swap.";
        };
      };

      credstore = {
        size = mkOption {
          type = types.str;
          default = "100M";
          description = "LUKS credstore volume size (only for ZFS). Stores encryption keys.";
        };
      };

      zfs = {
        compression = mkOption {
          type = types.enum ["off" "lz4" "zstd" "gzip" "gzip-1" "gzip-9"];
          default = "zstd";
          description = "Default compression algorithm for ZFS datasets";
        };

        atime = mkOption {
          type = types.enum ["on" "off"];
          default = "off";
          description = "Whether to update access time on file reads";
        };

        arcMax = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Maximum ARC cache size (e.g., '4G'). Null for automatic.";
          example = "4G";
        };

        autoSnapshot = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic ZFS snapshots";
        };

        autoScrub = mkOption {
          type = types.bool;
          default = true;
          description = "Enable weekly ZFS integrity scrub";
        };
      };
    };

    # Secure Boot configuration (x86 only)
    secureBoot = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Secure Boot with Lanzaboote";
      };
    };

    # TPM configuration (x86 only)
    tpm = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable TPM-based automatic disk unlock";
      };

      pcrs = mkOption {
        type = types.listOf types.int;
        default = [1 7];
        description = ''
          TPM PCRs to bind disk unlock to:
          - PCR 1: Firmware configuration
          - PCR 7: Secure Boot state
          Common alternatives: [7] for Secure Boot only (more update-resilient)
        '';
      };
    };

    # Remote unlock (initrd SSH)
    remoteUnlock = {
      enable = mkEnableOption "SSH remote disk unlock in initrd";

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          SSH public keys for remote unlock.
          If empty, keys are collected from all configured users.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 22;
        description = "SSH port for initrd remote unlock";
      };

      networkModule = mkOption {
        type = types.str;
        default = "virtio_net";
        description = "Network driver module to load in initrd";
        example = "e1000e";
      };

      dhcp = mkOption {
        type = types.bool;
        default = true;
        description = "Use DHCP for network configuration in initrd";
      };
    };

    # SSH server configuration
    ssh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SSH server for remote administration";
      };
    };

    # System services
    services = {
      avahi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Avahi/mDNS for network discovery (.local hostnames)";
        };
      };

      firewall = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable basic firewall (SSH port is opened automatically)";
        };
      };

      resolved = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable systemd-resolved for DNS resolution";
        };
      };
    };

    # Nix configuration
    nix = {
      gc = {
        automatic = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic Nix garbage collection";
        };
        dates = mkOption {
          type = types.str;
          default = "weekly";
          description = "Schedule for garbage collection";
        };
        options = mkOption {
          type = types.str;
          default = "--delete-older-than 30d";
          description = "Options passed to nix-collect-garbage";
        };
      };

      flakes = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nix flakes and nix-command";
      };
    };

    # User configuration
    users = mkOption {
      type = types.attrsOf userSubmodule;
      default = {};
      description = ''
        Users with automatic NixOS user creation, home-manager integration,
        and ZFS home directories with delegated permissions.
      '';
      example = literalExpression ''
        {
          alice = {
            fullName = "Alice Smith";
            email = "alice@example.com";
            extraGroups = [ "wheel" "networkmanager" ];
            authorizedKeys = [ "ssh-ed25519 AAAAC3... alice@laptop" ];
            terminal.enable = true;
            desktop.enable = true;
            zfs.quota = "100G";
          };
        }
      '';
    };
  };
}
