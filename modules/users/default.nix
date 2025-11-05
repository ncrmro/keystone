{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
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
                type = types.str;
                default = "lz4";
                description = "Compression algorithm for the dataset (off, lz4, zstd, gzip)";
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
    description = "Users with ZFS-backed home directories and delegated dataset management permissions";
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
        assertion =
          let
            uids = mapAttrsToList (_: u: u.uid) cfg;
            uniqueUids = unique uids;
          in
          length uids == length uniqueUids;
        message = "All user UIDs must be unique in keystone.users";
      }
    ];

    # Generate NixOS users with ZFS-backed home directories
    users.users = mapAttrs (username: userCfg: {
      isNormalUser = true;
      uid = userCfg.uid;
      description = userCfg.fullName;
      home = "/home/${username}";
      createHome = false; # ZFS dataset provides the home directory
      extraGroups = userCfg.extraGroups ++ ["zfs"]; # Add zfs group for /dev/zfs access
      initialPassword = userCfg.initialPassword;
      hashedPassword = userCfg.hashedPassword;
    }) cfg;

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

        # Validate rpool is imported
        if ! zpool list rpool > /dev/null 2>&1; then
          echo "ERROR: ZFS pool 'rpool' not found" >&2
          exit 1
        fi

        # Validate encrypted parent dataset exists
        if ! zfs list -H -o name rpool/crypt > /dev/null 2>&1; then
          echo "ERROR: Encrypted root dataset 'rpool/crypt' not found" >&2
          exit 1
        fi

        # Create parent home dataset if needed
        if ! zfs list -H -o name rpool/crypt/home > /dev/null 2>&1; then
          echo "Creating home dataset parent: rpool/crypt/home"
          zfs create -o mountpoint=/home rpool/crypt/home
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
        '') cfg)}

        echo "All ZFS user datasets configured successfully"
      '';
    };
  };
}
