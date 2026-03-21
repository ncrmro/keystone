# Keystone OS Users Module
#
# Creates users with:
# - NixOS user accounts with proper groups and authentication
# - ZFS home directories with delegated permissions and quotas
# - Optional home-manager integration for terminal/desktop config
#
# SSH keys are read from keystone.keys.<username> — all host keys
# plus all hardware keys are added to authorized_keys.
#
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.users;
  keysCfg = config.keystone.keys;
  hostname = config.networking.hostName;

  # Look up the current host's devMode from keystone.hosts (FR-014)
  hostEntries = attrValues config.keystone.hosts;
  matchedHost = filter (h: h.hostname == hostname) hostEntries;
  currentHostDevMode = if matchedHost != [ ] then (head matchedHost).devMode else false;

  # Whether the keystone desktop NixOS module is imported (gates home-manager desktop config)
  hasDesktopModule = options.keystone ? desktop;

  # Check if ZFS is being used
  # TODO: Re-evaluate ZFS home folder management. Current implementation can interfere with legacy setups.
  useZfs = osCfg.storage.type == "zfs" && osCfg.storage.enable;

  # All public keys for a user (all hosts + all hardware keys)
  allKeysFor =
    username:
    let
      u = keysCfg.${username};
      hostKeys = mapAttrsToList (_: h: h.publicKey) u.hosts;
      hwKeys = mapAttrsToList (_: h: h.publicKey) u.hardwareKeys;
    in
    hostKeys ++ hwKeys;

  # Public keys valid on a specific host for a user
  # (that host's software key + all hardware keys)
  keysForUserOnHost =
    username: hn:
    let
      u = keysCfg.${username};
      hostKey = optional (u.hosts ? ${hn}) u.hosts.${hn}.publicKey;
      hwKeys = mapAttrsToList (_: h: h.publicKey) u.hardwareKeys;
    in
    hostKey ++ hwKeys;
in
{
  config = mkMerge [
    (mkIf (osCfg.enable && cfg != { }) {
      # Enable ZFS delegation for non-root users (only if using ZFS)
      boot.extraModprobeConfig = mkIf useZfs ''
        options zfs zfs_admin_snapshot=1
      '';

      # Create zfs group for /dev/zfs access
      users.groups.zfs = mkIf useZfs { };

      # Set /dev/zfs permissions
      services.udev.extraRules = mkIf useZfs ''
        KERNEL=="zfs", MODE="0660", GROUP="zfs"
      '';

      # Assertions
      assertions = [
        {
          assertion =
            !useZfs
            || (
              config.boot.supportedFilesystems ? "zfs" || elem "zfs" (attrNames config.boot.supportedFilesystems)
            );
          message = "ZFS must be enabled when using ZFS storage";
        }
        {
          assertion =
            let
              uids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) cfg);
              uniqueUids = unique uids;
            in
            length uids == length uniqueUids;
          message = "All user UIDs must be unique";
        }
      ]
      # Validate agenix secret exists when sshAutoLoad is enabled
      # (auto-declared below when secrets.repo is set, so this only fires
      # when secrets.repo is null and no manual declaration exists)
      ++ concatLists (
        mapAttrsToList (
          username: userCfg:
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

              If keystone.secrets.repo is set, the age.secrets declaration is automatic.
              Otherwise, add manually to host config:
                age.secrets.${hostname}-ssh-passphrase = {
                  file = "${"$"}{inputs.agenix-secrets}/secrets/${hostname}-ssh-passphrase.age";
                  owner = "${username}";
                  mode = "0400";
                };
            '';
          }
        ) cfg
      );

      # Auto-declare age.secrets for sshAutoLoad when secrets.repo is set
      age.secrets = mkIf (config.keystone.secrets.repo != null) (
        listToAttrs (
          concatLists (
            mapAttrsToList (
              username: userCfg:
              optional userCfg.sshAutoLoad.enable (
                nameValuePair "${hostname}-ssh-passphrase" {
                  file = "${config.keystone.secrets.repo}/secrets/${hostname}-ssh-passphrase.age";
                  owner = username;
                  mode = "0400";
                }
              )
            ) cfg
          )
        )
      );

      # Enable zsh system-wide if any user has terminal enabled
      programs.zsh.enable = mkIf (any (u: u.terminal.enable) (attrValues cfg)) true;

      # Generate NixOS users
      users.users = mapAttrs (username: userCfg: {
        isNormalUser = true;
        uid = userCfg.uid;
        description = userCfg.fullName;
        home = "/home/${username}";
        createHome = !useZfs; # Let ZFS dataset provide home when using ZFS
        extraGroups = unique (userCfg.extraGroups ++ (optionals useZfs [ "zfs" ]));
        initialPassword = userCfg.initialPassword;
        hashedPassword = userCfg.hashedPassword;
        # Read all keys from keystone.keys registry
        openssh.authorizedKeys.keys = if keysCfg ? ${username} then allKeysFor username else [ ];
        shell = mkIf userCfg.terminal.enable pkgs.zsh;
      }) cfg;

      # Home directory ownership for ext4 (ZFS handles this in its service)
      systemd.services.create-user-homes = mkIf (!useZfs) {
        description = "Create and configure user home directories";

        wantedBy = [ "multi-user.target" ];
        before = [
          "display-manager.service"
          "systemd-user-sessions.service"
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (username: userCfg: ''
              if [ ! -d /home/${username} ]; then
                mkdir -p /home/${username}
              fi
              chown ${username}:users /home/${username}
              chmod 700 /home/${username}
            '') cfg
          )}
        '';
      };
    })

    # Configure home-manager for users with terminal/desktop enabled
    # This requires home-manager to be imported in the system configuration
    # NOTE: This must be a separate mkMerge entry, not merged with // into the
    # mkIf block above. Using // on a mkIf value silently drops the merged keys
    # because the module system only reads the mkIf's `content` attribute.
    (optionalAttrs (options ? home-manager) {
      home-manager =
        mkIf (osCfg.enable && cfg != { } && any (u: u.terminal.enable || u.desktop.enable) (attrValues cfg))
          {
            useGlobalPkgs = mkDefault true;
            useUserPackages = mkDefault true;

            users = mapAttrs (
              username: userCfg:
              { pkgs, ... }:
              {
                home.username = username;
                home.homeDirectory = "/home/${username}";
                home.stateVersion = config.system.stateVersion;

                # Terminal development environment
                keystone.terminal = mkIf userCfg.terminal.enable (
                  {
                    enable = mkDefault true;
                    devMode = mkDefault currentHostDevMode;
                    git = {
                      enable = mkDefault (userCfg.email != null);
                      userName = mkDefault userCfg.fullName;
                      userEmail = mkDefault userCfg.email;
                      # Bridge SSH public keys from keystone.keys for allowed_signers
                      sshPublicKeys = mkDefault (if keysCfg ? ${username} then allKeysFor username else [ ]);
                      # TODO: Bridge forgejo.domain/sshPort/username here once the users.nix
                      # home-manager bridge mkIf issue is resolved. Currently the entire mkIf
                      # block is dead code for users whose home-manager config is also defined
                      # in nixos-config (the nixos-config definitions take precedence and this
                      # bridge's mkIf values are never applied — even mkForce has no effect).
                      # See: https://github.com/ncrmro/keystone/issues/XXX
                      forgejo.enable = mkDefault (config.keystone.services.git.host != null);
                    };
                  }
                  // optionalAttrs userCfg.sshAutoLoad.enable {
                    sshAutoLoad.enable = mkDefault true;
                  }
                );
              }
              // optionalAttrs hasDesktopModule {
                # Desktop configuration (Hyprland) — only set when desktop NixOS module is imported
                keystone.desktop = mkIf userCfg.desktop.enable {
                  enable = mkDefault true;
                  hyprland = {
                    enable = mkDefault true;
                    modifierKey = mkDefault userCfg.desktop.hyprland.modifierKey;
                    capslockAsControl = mkDefault userCfg.desktop.hyprland.capslockAsControl;
                  };
                };
              }
            ) (filterAttrs (_: u: u.terminal.enable || u.desktop.enable) cfg);
          };
    })
  ];
}
