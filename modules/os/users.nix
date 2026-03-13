# Keystone OS Users Module
#
# Creates users with:
# - NixOS user accounts with proper groups and authentication
# - ZFS home directories with delegated permissions and quotas
# - Optional home-manager integration for terminal/desktop config
#
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
  cfg = osCfg.users;
  hwKeyCfg = config.keystone.hardwareKey;
  hostname = config.networking.hostName;

  # Whether the keystone desktop NixOS module is imported (gates home-manager desktop config)
  hasDesktopModule = options.keystone ? desktop;

  # Check if ZFS is being used
  # TODO: Re-evaluate ZFS home folder management. Current implementation can interfere with legacy setups.
  useZfs = osCfg.storage.type == "zfs" && osCfg.storage.enable;

  # Resolve hardware key names to SSH public keys for a user
  resolveHardwareKeys = userCfg:
    map (name: hwKeyCfg.keys.${name}.sshPublicKey) userCfg.hardwareKeys;
in {
  config = mkMerge [
    (mkIf (osCfg.enable && cfg != {}) {
      # Enable ZFS delegation for non-root users (only if using ZFS)
      boot.extraModprobeConfig = mkIf useZfs ''
        options zfs zfs_admin_snapshot=1
      '';

      # Create zfs group for /dev/zfs access
      users.groups.zfs = mkIf useZfs {};

      # Set /dev/zfs permissions
      services.udev.extraRules = mkIf useZfs ''
        KERNEL=="zfs", MODE="0660", GROUP="zfs"
      '';

      # Assertions
      assertions = [
        {
          assertion = !useZfs || (config.boot.supportedFilesystems ? "zfs" || elem "zfs" (attrNames config.boot.supportedFilesystems));
          message = "ZFS must be enabled when using ZFS storage";
        }
        {
          assertion = let
            uids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) cfg);
            uniqueUids = unique uids;
          in
            length uids == length uniqueUids;
          message = "All user UIDs must be unique";
        }
      ]
      # Validate hardwareKeys references exist in keystone.hardwareKey.keys
      ++ concatLists (mapAttrsToList (username: userCfg:
        map (name: {
          assertion = hwKeyCfg.keys ? ${name};
          message = "keystone.os.users.${username}.hardwareKeys references '${name}' but no such key exists in keystone.hardwareKey.keys";
        }) userCfg.hardwareKeys
      ) cfg)
      # Validate agenix secret exists when sshAutoLoad is enabled
      # (auto-declared below when secretsBasePath is set, so this only fires
      # when secretsBasePath is null and no manual declaration exists)
      ++ concatLists (mapAttrsToList (username: userCfg:
        optional userCfg.sshAutoLoad.enable {
          assertion = config.age.secrets ? "${hostname}-ssh-passphrase";
          message = ''
            User '${username}' has sshAutoLoad enabled but the secret file "${hostname}-ssh-passphrase.age" is missing.

            1. Add to agenix-secrets/secrets.nix:
               "secrets/${hostname}-ssh-passphrase.age".publicKeys = adminKeys ++ [ systems.${hostname} ];

            2. Create the secret (enter the SSH key passphrase):
               cd agenix-secrets && agenix -e secrets/${hostname}-ssh-passphrase.age

            3. Commit, push, and update flake:
               git add -A && git commit -m "Add ${hostname} SSH passphrase" && git push
               cd .. && nix flake update agenix-secrets

            If keystone.os.secretsBasePath is set, the age.secrets declaration is automatic.
            Otherwise, add manually to host config:
              age.secrets.${hostname}-ssh-passphrase = {
                file = "${"$"}{inputs.agenix-secrets}/secrets/${hostname}-ssh-passphrase.age";
                owner = "${username}";
                mode = "0400";
              };
          '';
        }
      ) cfg);

      # Auto-declare age.secrets for sshAutoLoad when secretsBasePath is set
      age.secrets = mkIf (osCfg.secretsBasePath != null) (
        listToAttrs (concatLists (mapAttrsToList (username: userCfg:
          optional userCfg.sshAutoLoad.enable (nameValuePair "${hostname}-ssh-passphrase" {
            file = "${osCfg.secretsBasePath}/secrets/${hostname}-ssh-passphrase.age";
            owner = username;
            mode = "0400";
          })
        ) cfg))
      );

      # Enable zsh system-wide if any user has terminal enabled
      programs.zsh.enable = mkIf (any (u: u.terminal.enable) (attrValues cfg)) true;

      # Generate NixOS users
      users.users =
        mapAttrs (username: userCfg: {
          isNormalUser = true;
          uid = userCfg.uid;
          description = userCfg.fullName;
          home = "/home/${username}";
          createHome = !useZfs; # Let ZFS dataset provide home when using ZFS
          extraGroups = unique (userCfg.extraGroups ++ (optionals useZfs ["zfs"]));
          initialPassword = userCfg.initialPassword;
          hashedPassword = userCfg.hashedPassword;
          openssh.authorizedKeys.keys = userCfg.authorizedKeys ++ (resolveHardwareKeys userCfg);
          shell = mkIf userCfg.terminal.enable pkgs.zsh;
        })
        cfg;

      /*
      # ZFS dataset creation service (only if using ZFS)
      # TODO: Re-evaluate ZFS home folder management before re-enabling.
      systemd.services.zfs-user-datasets = mkIf useZfs {
        description = "Create ZFS datasets for user home directories";

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

              # Create dataset with mountpoint
              zfs create -p -o mountpoint=/home/${username} rpool/crypt/home/${username} 2>/dev/null || true

              # Set ZFS properties
              zfs set compression=${userCfg.zfs.compression} rpool/crypt/home/${username}
              ${optionalString (userCfg.zfs.quota != null) ''
                zfs set quota=${userCfg.zfs.quota} rpool/crypt/home/${username}
              ''}
              ${optionalString (userCfg.zfs.recordsize != null) ''
                zfs set recordsize=${userCfg.zfs.recordsize} rpool/crypt/home/${username}
              ''}
              zfs set atime=${userCfg.zfs.atime} rpool/crypt/home/${username}

              # Grant delegation permissions
              zfs allow -u ${username} create,mount,mountpoint,snapshot,rollback,diff,send,receive,hold,release,bookmark,compression,quota,refquota,recordsize,atime,readonly,userprop rpool/crypt/home/${username}

              # Allow destroy only on descendants
              zfs allow -d -u ${username} destroy rpool/crypt/home/${username}

              # Set filesystem ownership
              chown ${username}:users /home/${username}
              chmod 700 /home/${username}

              echo "  ✓ Dataset configured: rpool/crypt/home/${username}"
            '')
            cfg)}

          echo "All ZFS user datasets configured successfully"
        '';
      };
      */

      # Home directory ownership for ext4 (ZFS handles this in its service)
      systemd.services.create-user-homes = mkIf (!useZfs) {
        description = "Create and configure user home directories";

        wantedBy = ["multi-user.target"];
        before = ["display-manager.service" "systemd-user-sessions.service"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (mapAttrsToList (username: userCfg: ''
              if [ ! -d /home/${username} ]; then
                mkdir -p /home/${username}
              fi
              chown ${username}:users /home/${username}
              chmod 700 /home/${username}
            '')
            cfg)}
        '';
      };
    })

    # Configure home-manager for users with terminal/desktop enabled
    # This requires home-manager to be imported in the system configuration
    # NOTE: This must be a separate mkMerge entry, not merged with // into the
    # mkIf block above. Using // on a mkIf value silently drops the merged keys
    # because the module system only reads the mkIf's `content` attribute.
    (optionalAttrs (options ? home-manager) {
      home-manager = mkIf (osCfg.enable && cfg != {} && any (u: u.terminal.enable || u.desktop.enable) (attrValues cfg)) {
        useGlobalPkgs = mkDefault true;
        useUserPackages = mkDefault true;

        users = mapAttrs (username: userCfg: {pkgs, ...}: {
          home.username = username;
          home.homeDirectory = "/home/${username}";
          home.stateVersion = config.system.stateVersion;

          # Terminal development environment
          keystone.terminal = mkIf userCfg.terminal.enable ({
            enable = mkDefault true;
            git = {
              enable = mkDefault (userCfg.email != null);
              userName = mkDefault userCfg.fullName;
              userEmail = mkDefault userCfg.email;
              forgejo.enable = mkDefault (config.keystone.services.git.host != null);
            };
          } // optionalAttrs userCfg.sshAutoLoad.enable {
            sshAutoLoad.enable = mkDefault true;
          });
        } // optionalAttrs hasDesktopModule {
          # Desktop configuration (Hyprland) — only set when desktop NixOS module is imported
          keystone.desktop = mkIf userCfg.desktop.enable {
            enable = mkDefault true;
            hyprland = {
              enable = mkDefault true;
              modifierKey = mkDefault userCfg.desktop.hyprland.modifierKey;
              capslockAsControl = mkDefault userCfg.desktop.hyprland.capslockAsControl;
            };
          };
        }) (filterAttrs (_: u: u.terminal.enable || u.desktop.enable) cfg);
      };
    })
  ];
}
