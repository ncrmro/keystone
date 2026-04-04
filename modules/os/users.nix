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
  legacyAdminCfg = if cfg ? admin then cfg.admin else null;
  effectiveAdminCfg = if osCfg.admin != null then osCfg.admin else legacyAdminCfg;
  effectiveUsers =
    (removeAttrs cfg [ "admin" ])
    // optionalAttrs (effectiveAdminCfg != null) {
      admin = effectiveAdminCfg // {
        extraGroups = unique ([ "wheel" ] ++ effectiveAdminCfg.extraGroups);
      };
    };
  keysCfg = config.keystone.keys;
  hostname = config.networking.hostName;
  immichServiceCfg = config.keystone.services.immich;

  # Whether the keystone desktop NixOS module is imported (gates home-manager desktop config)
  hasDesktopModule = options.keystone ? desktop;
  desktopUsers = filterAttrs (_: userCfg: userCfg.desktop.enable) effectiveUsers;
  desktopUsernames = attrNames desktopUsers;
  inferredDesktopUser = if desktopUsernames == [ ] then null else head desktopUsernames;
  desktopAccessGroups = [
    "networkmanager"
    "video"
    "audio"
  ];

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

  screenshotUsers = filterAttrs (
    _: userCfg: userCfg.desktop.enable && userCfg.desktop.screenshotSync.enable
  ) effectiveUsers;

  immichServerUrl =
    let
      immichHostName = immichServiceCfg.host;
      hostEntry = findFirst (h: h.hostname == immichHostName) null (attrValues config.keystone.hosts);
      hostTarget =
        if hostEntry == null then
          immichHostName
        else if hostEntry.tailscaleIP != null then
          hostEntry.tailscaleIP
        else if hostEntry.sshTarget != null then
          hostEntry.sshTarget
        else if hostEntry.fallbackIP != null then
          hostEntry.fallbackIP
        else
          immichHostName;
    in
    if config.keystone.domain != null then
      "https://photos.${config.keystone.domain}"
    else
      "http://${hostTarget}:2283";
in
{
  config = mkMerge [
    (mkIf (osCfg.enable && effectiveUsers != { }) {
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
          assertion = effectiveAdminCfg != null;
          message = "Keystone OS requires keystone.os.admin to define the canonical administrator.";
        }
        {
          assertion = !(osCfg.admin != null && legacyAdminCfg != null);
          message = "Define the administrator in keystone.os.admin, not both keystone.os.admin and keystone.os.users.admin.";
        }
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
              uids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) effectiveUsers);
              uniqueUids = unique uids;
            in
            length uids == length uniqueUids;
          message = "All user UIDs must be unique";
        }
      ]
      ++ concatLists (
        mapAttrsToList (
          username: userCfg:
          optional userCfg.desktop.screenshotSync.enable {
            assertion = userCfg.desktop.enable;
            message = "User '${username}' enables desktop.screenshotSync but desktop.enable is false.";
          }
        ) effectiveUsers
      )
      ++ optionals (screenshotUsers != { }) [
        {
          assertion = immichServiceCfg.host != null;
          message = "Desktop screenshot sync requires keystone.services.immich.host to be set.";
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
        ) effectiveUsers
      );

      warnings =
        optional (osCfg.admin != null && legacyAdminCfg != null) ''
          Both keystone.os.admin and keystone.os.users.admin are set. Use keystone.os.admin only.
        ''
        ++ optional (osCfg.admin == null && legacyAdminCfg != null) ''
          keystone.os.users.admin is deprecated. Move the administrator definition to keystone.os.admin.
        ''
        ++ concatLists (
          mapAttrsToList (
            username: userCfg:
            optional
              (userCfg.desktop.screenshotSync.enable && !(config.age.secrets ? "${username}-immich-api-key"))
              ''
                Screenshot sync is enabled for user '${username}', but agenix secret "${username}-immich-api-key" is not declared yet.

                To finish setup:
                1. Add to agenix-secrets/secrets.nix:
                   "secrets/${username}-immich-api-key.age".publicKeys = adminKeys ++ [ systems.${hostname} ];
                2. Create the secret with the user's Immich API key:
                   cd agenix-secrets && agenix -e secrets/${username}-immich-api-key.age
                3. If keystone.secrets.repo is null, declare it in host config:
                   age.secrets.${username}-immich-api-key = {
                     file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-immich-api-key.age";
                     owner = "${username}";
                     mode = "0400";
                   };

                TODO: automate Immich API key provisioning and secret enrollment from Keystone tooling.
              ''
          ) screenshotUsers
        )
        ++ optional (hasDesktopModule && length desktopUsernames > 1) ''
          Multiple users have keystone.os.users.<name>.desktop.enable = true. Keystone defaulted keystone.desktop.user to "${inferredDesktopUser}".

          Set keystone.desktop.user explicitly if a different desktop login user should own the session.
        '';

      # Auto-declare age.secrets for sshAutoLoad when secrets.repo is set
      age.secrets = mkIf (config.keystone.secrets.repo != null) (
        listToAttrs (
          concatLists (
            mapAttrsToList (
              username: userCfg:
              (optional userCfg.sshAutoLoad.enable (
                nameValuePair "${hostname}-ssh-passphrase" {
                  file = "${config.keystone.secrets.repo}/secrets/${hostname}-ssh-passphrase.age";
                  owner = username;
                  mode = "0400";
                }
              ))
              ++ (optional userCfg.desktop.screenshotSync.enable (
                nameValuePair "${username}-immich-api-key" {
                  file = "${config.keystone.secrets.repo}/secrets/${username}-immich-api-key.age";
                  owner = username;
                  mode = "0400";
                }
              ))
            ) effectiveUsers
          )
        )
      );

      # Enable zsh system-wide if any user has terminal enabled
      programs.zsh.enable = mkIf (any (u: u.terminal.enable) (attrValues effectiveUsers)) true;

      # Generate NixOS users
      users.users = mapAttrs (username: userCfg: {
        isNormalUser = true;
        uid = userCfg.uid;
        description = userCfg.fullName;
        home = "/home/${username}";
        createHome = !useZfs; # Let ZFS dataset provide home when using ZFS
        extraGroups = unique (
          userCfg.extraGroups
          ++ optionals (hasDesktopModule && userCfg.desktop.enable) desktopAccessGroups
          ++ (optionals useZfs [ "zfs" ])
        );
        initialPassword = userCfg.initialPassword;
        hashedPassword = userCfg.hashedPassword;
        # Read all keys from keystone.keys registry
        openssh.authorizedKeys.keys = if keysCfg ? ${username} then allKeysFor username else [ ];
        shell = mkIf userCfg.terminal.enable pkgs.zsh;
      }) effectiveUsers;

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
            '') effectiveUsers
          )}
        '';
      };

      systemd.user.services = mkMerge (
        mapAttrsToList (
          username: userCfg:
          mkIf userCfg.desktop.screenshotSync.enable {
            "keystone-${username}-screenshot-sync" = {
              description = "Sync screenshots to Immich for ${username}";
              unitConfig.ConditionUser = username;
              serviceConfig = {
                Type = "oneshot";
                SyslogIdentifier = "keystone-screenshot-sync";
              };
              script = ''
                export HOME=/home/${username}
                export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
                exec ${pkgs.keystone.keystone-photos}/bin/keystone-photos sync-screenshots \
                  --url ${lib.escapeShellArg immichServerUrl} \
                  --api-key-file /run/agenix/${username}-immich-api-key \
                  --album-name ${lib.escapeShellArg "Screenshots - ${username}"} \
                  --host-name ${lib.escapeShellArg hostname} \
                  --account-name ${lib.escapeShellArg username} \
                  --state-file "''${XDG_STATE_HOME}/keystone-photos/screenshot-sync.tsv"
              '';
            };
          }
        ) screenshotUsers
      );

      systemd.user.timers = mkMerge (
        mapAttrsToList (
          username: userCfg:
          mkIf userCfg.desktop.screenshotSync.enable {
            "keystone-${username}-screenshot-sync" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = userCfg.desktop.screenshotSync.syncOnCalendar;
                Persistent = true;
              };
            };
          }
        ) screenshotUsers
      );
    })

    # Configure home-manager for users with terminal/desktop enabled
    # This requires home-manager to be imported in the system configuration
    # NOTE: This must be a separate mkMerge entry, not merged with // into the
    # mkIf block above. Using // on a mkIf value silently drops the merged keys
    # because the module system only reads the mkIf's `content` attribute.
    (optionalAttrs (options ? home-manager) {
      home-manager =
        mkIf
          (
            osCfg.enable
            && effectiveUsers != { }
            && any (u: u.terminal.enable || u.desktop.enable) (attrValues effectiveUsers)
          )
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
                # NOTE: Do NOT wrap this in mkIf — mkIf inside function-type
                # home-manager.users definitions silently fails to merge when
                # another module also defines the same user. Use mkDefault on
                # enable instead; the terminal module's own config = mkIf cfg.enable
                # handles gating.
                keystone.terminal = {
                  enable = mkDefault userCfg.terminal.enable;
                  aiExtensions.capabilities = mkDefault userCfg.capabilities;

                  # development and repos are no longer bridged here;
                  # they are inherited globally from keystone.development
                  # and keystone.repos which are now shared options.

                  git = {
                    enable = mkDefault (userCfg.terminal.enable && userCfg.email != null);
                    userName = mkDefault userCfg.fullName;
                    userEmail = mkDefault userCfg.email;
                    # Bridge SSH public keys from keystone.keys for allowed_signers
                    sshPublicKeys = mkDefault (if keysCfg ? ${username} then allKeysFor username else [ ]);
                    forgejo.enable = mkDefault (config.keystone.services.git.host != null);
                  };

                  sshAutoLoad.enable = mkDefault userCfg.sshAutoLoad.enable;
                };
              }
              // optionalAttrs hasDesktopModule {
                # Desktop configuration (Hyprland) — only set when desktop NixOS module is imported
                keystone.desktop = mkIf userCfg.desktop.enable {
                  enable = mkDefault true;
                  uhk.enable = mkDefault config.keystone.hardware.uhk.enable;
                  hyprland = {
                    enable = mkDefault true;
                    modifierKey = mkDefault userCfg.desktop.hyprland.modifierKey;
                    capslockAsControl = mkDefault userCfg.desktop.hyprland.capslockAsControl;
                  };
                };
              }
            ) (filterAttrs (_: u: u.terminal.enable || u.desktop.enable) effectiveUsers);
          };
    })

    # Bridge per-user desktop intent into the top-level desktop module when it is imported.
    (optionalAttrs hasDesktopModule {
      keystone.desktop = mkIf (osCfg.enable && desktopUsernames != [ ]) {
        enable = mkDefault true;
        user = mkDefault inferredDesktopUser;
      };
    })
  ];
}
