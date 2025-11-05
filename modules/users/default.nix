# User Management with ZFS-backed Home Directories
#
# This module creates users with ZFS datasets and delegated permissions.
#
# NOTE: Any changes to this module should be reflected in docs/users.md
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkOption
    mkIf
    types
    mapAttrs
    mapAttrsToList
    concatStringsSep
    optionalString
    unique
    elem
    attrNames
    attrValues
    all
    literalExpression
    length
    ;
  cfg = config.keystone.users;
in {
  options.keystone.users = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        uid = mkOption {
          type = types.int;
          description = "User ID for the system user";
        };

        fullName = mkOption {
          type = types.str;
          default = "";
          description = "Full name or description of the user (GECOS field)";
        };

        extraGroups = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional groups the user should be a member of";
        };

        initialPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Initial password for the user (plaintext). WARNING: Stored in Nix store. Use hashedPassword for production.";
        };

        hashedPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Hashed password for the user (generate with mkpasswd -m sha-512)";
        };

        zfsProperties = mkOption {
          type = types.submodule {
            options = {
              quota = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Storage quota for the user (includes all child datasets and snapshots). Format: 100G, 1T, etc.";
              };

              compression = mkOption {
                type = types.enum ["off" "on" "lz4" "gzip" "gzip-1" "gzip-2" "gzip-3" "gzip-4" "gzip-5" "gzip-6" "gzip-7" "gzip-8" "gzip-9" "zstd" "zstd-fast" "lzjb"];
                default = "lz4";
                description = "Compression algorithm for the dataset";
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
          default = {};
          description = "ZFS properties to set on the user's home dataset";
        };
      };
    });
    default = {};
    example = literalExpression ''
      {
        alice = {
          uid = 1000;
          fullName = "Alice Smith";
          extraGroups = [ "wheel" "networkmanager" ];
          hashedPassword = "$6$rounds=656000$...";
          zfsProperties = {
            quota = "500G";
            compression = "zstd";
            recordsize = "128K";
          };
        };
      }
    '';
    description = ''
      Users with ZFS-backed home directories and delegated dataset management permissions.

      Each user gets:
      - A ZFS dataset at rpool/crypt/home/<username>
      - Delegated ZFS permissions for snapshots, sends, receives, and property management
      - Membership in the 'zfs' group for /dev/zfs access
      - Automatic home directory creation and ownership
    '';
  };

  config = mkIf (cfg != {}) {
    # Enable ZFS delegation for non-root users
    boot.extraModprobeConfig = ''
      options zfs zfs_admin_snapshot=1
    '';

    # Create zfs group for /dev/zfs access
    users.groups.zfs = {};

    # Set /dev/zfs permissions to allow zfs group members to use delegation
    services.udev.extraRules = ''
      KERNEL=="zfs", MODE="0660", GROUP="zfs"
    '';

    # Assertions
    assertions = [
      {
        assertion = config.boot.supportedFilesystems ? "zfs" || elem "zfs" (attrNames config.boot.supportedFilesystems);
        message = "ZFS must be enabled (boot.supportedFilesystems must include 'zfs')";
      }
      {
        assertion = let
          uids = mapAttrsToList (_: u: u.uid) cfg;
          uniqueUids = unique uids;
        in
          length uids == length uniqueUids;
        message = "All user UIDs must be unique in keystone.users";
      }
      {
        assertion = all (user: user.initialPassword != null || user.hashedPassword != null) (attrValues cfg);
        message = "All keystone users must have either initialPassword or hashedPassword set";
      }
    ];

    # Generate NixOS users with ZFS-backed home directories
    users.users =
      mapAttrs (username: userCfg: {
        isNormalUser = true;
        uid = userCfg.uid;
        description = userCfg.fullName;
        home = "/home/${username}";
        createHome = false; # ZFS dataset provides the home directory
        extraGroups = unique (userCfg.extraGroups ++ ["zfs"]); # Add zfs group for /dev/zfs access, prevent duplicates
        initialPassword = userCfg.initialPassword;
        hashedPassword = userCfg.hashedPassword;
      })
      cfg;

    # Systemd service for ZFS dataset creation and permission delegation
    systemd.services.zfs-user-datasets = {
      description = "Create ZFS datasets for user home directories with delegated permissions";

      wantedBy = ["multi-user.target"];
      after = ["zfs-mount.service"];
      before = ["display-manager.service" "systemd-user-sessions.service"];
      requires = ["zfs-mount.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [config.boot.zfs.package];

      script = ''
        set -euo pipefail

        log() {
          echo "[zfs-user-datasets] $*"
        }

        error() {
          echo "[zfs-user-datasets] ERROR: $*" >&2
          exit 1
        }

        # Validate rpool is imported
        if ! zpool list rpool > /dev/null 2>&1; then
          error "ZFS pool 'rpool' not found or not imported"
        fi

        log "ZFS pool 'rpool' is available"

        # Validate encrypted parent dataset exists
        if ! zfs list -H -o name rpool/crypt > /dev/null 2>&1; then
          error "Encrypted root dataset 'rpool/crypt' not found"
        fi

        log "Encrypted root dataset 'rpool/crypt' found"

        # Create parent home dataset if needed
        if ! zfs list -H -o name rpool/crypt/home > /dev/null 2>&1; then
          log "Creating home dataset parent: rpool/crypt/home"
          zfs create -o mountpoint=/home rpool/crypt/home
        else
          log "Home dataset parent already exists: rpool/crypt/home"
        fi

        # Create datasets for each configured user
        ${concatStringsSep "\n" (mapAttrsToList (username: userCfg: ''
            echo "Configuring ZFS dataset for user: ${username}"

            # Create dataset with mountpoint (idempotent with -p flag)
            zfs create -p -o mountpoint=/home/${username} rpool/crypt/home/${username}

            # Set ZFS properties (always safe to rerun)
            zfs set compression=${userCfg.zfsProperties.compression} rpool/crypt/home/${username}
            ${optionalString (userCfg.zfsProperties.quota != null) ''
              zfs set quota=${userCfg.zfsProperties.quota} rpool/crypt/home/${username}
            ''}
            ${optionalString (userCfg.zfsProperties.recordsize != null) ''
              zfs set recordsize=${userCfg.zfsProperties.recordsize} rpool/crypt/home/${username}
            ''}
            zfs set atime=${userCfg.zfsProperties.atime} rpool/crypt/home/${username}

            # Grant delegation permissions for full dataset management (idempotent)
            # Note: mount/mountpoint permissions are granted but Linux kernel restricts actual mounting to root
            zfs allow -u ${username} create,mount,mountpoint,snapshot,rollback,diff,send,receive,hold,release,bookmark,compression,quota,refquota,recordsize,atime,readonly,userprop rpool/crypt/home/${username}

            # Allow destroy only on descendants (protects parent home dataset)
            zfs allow -d -u ${username} destroy rpool/crypt/home/${username}

            # Set filesystem ownership and permissions
            chown ${username}:users /home/${username}
            chmod 700 /home/${username}

            echo "  ✓ Dataset created/updated: rpool/crypt/home/${username}"
          '')
          cfg)}

        echo "All ZFS user datasets configured successfully"
      '';
    };
  };
}
