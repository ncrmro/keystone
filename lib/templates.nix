{
  self,
  nixpkgs,
  home-manager,
  lib,
}:
let
  withDesktopUser =
    userCfg:
    # Desktop archetypes should be ready out of the box for the administrator.
    # Individual hosts can still opt out by setting desktop.enable = false.
    lib.recursiveUpdate {
      desktop.enable = true;
    } userCfg;

  mkHostModule =
    {
      hostname,
      stateVersion ? "25.05",
      timeZone ? "UTC",
      storage,
      admin,
      adminUsername ? "keystone",
      users,
      secureBoot ? {
        enable = true;
      },
      tpm ? {
        enable = true;
        pcrs = [
          1
          7
        ];
      },
      ssh ? {
        enable = true;
      },
      remoteUnlock ? {
        enable = false;
      },
      config ? { },
    }:
    lib.recursiveUpdate {
      networking.hostName = hostname;
      system.stateVersion = stateVersion;
      time.timeZone = timeZone;
      boot.loader.systemd-boot.enable = lib.mkDefault true;

      # Apply keystone overlay so pkgs.keystone.* packages are available
      nixpkgs.overlays = [ self.overlays.default ];

      keystone.os = {
        enable = true;
        # Tailscale requires hosts registry — template configs don't have one
        tailscale.enable = lib.mkDefault false;
        inherit
          adminUsername
          storage
          secureBoot
          tpm
          ssh
          remoteUnlock
          ;
        # Merge the admin user into users at adminUsername with admin = true.
        # This is the single source of truth for administrator identity;
        # other entries in users are regular (non-admin) users.
        users = users // {
          ${adminUsername} = admin // {
            admin = true;
          };
        };
      };

      nix.settings.trusted-users = [
        "root"
        "@wheel"
      ];
    } config;

  mkLinuxHost =
    {
      system ? "x86_64-linux",
      hostname,
      stateVersion ? "25.05",
      timeZone ? "UTC",
      storage,
      admin,
      adminUsername ? "keystone",
      users ? { },
      desktop ? false,
      secureBoot ? {
        enable = true;
      },
      tpm ? {
        enable = true;
        pcrs = [
          1
          7
        ];
      },
      ssh ? {
        enable = true;
      },
      remoteUnlock ? {
        enable = false;
      },
      config ? { },
      nixosModules ? [ ],
      modules ? [ ],
      # specialArgs are forwarded directly to nixpkgs.lib.nixosSystem so
      # consumer modules using `{ inputs, outputs, ... }:` can be evaluated
      # without triggering `_module.args`-based infinite recursion. Defining
      # `inputs` via `_module.args` works for runtime config but breaks when
      # a module uses `inputs` inside its own `imports = [ ... ];` list.
      specialArgs ? { },
    }:
    nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules = [
        self.nixosModules.operating-system
      ]
      ++ lib.optionals desktop [ self.nixosModules.desktop ]
      ++ nixosModules
      ++ [
        (mkHostModule {
          inherit
            hostname
            stateVersion
            timeZone
            storage
            admin
            adminUsername
            users
            secureBoot
            tpm
            ssh
            remoteUnlock
            config
            ;
        })
      ]
      ++ modules;
    };

  mkSharedLinuxHostHelper =
    defaults: archetype:
    {
      hostname,
      admin ? defaults.admin,
      users ? { },
      modules ? [ ],
      ...
    }@args:
    let
      hostModules = if defaults ? hostModules then defaults.hostModules hostname else [ ];
    in
    archetype (
      (builtins.removeAttrs args [
        "admin"
        "users"
        "modules"
      ])
      // {
        system = if args ? system then args.system else defaults.system or "x86_64-linux";
        timeZone = if args ? timeZone then args.timeZone else defaults.timeZone or "UTC";
        inherit admin;
        users = (defaults.users or { }) // users;
        modules = (defaults.modules or [ ]) ++ hostModules ++ modules;
      }
    );

  mkSharedMacosHomeHelper =
    defaults:
    {
      system ? defaults.system or "aarch64-darwin",
      username ? defaults.username or "admin",
      fullName ? defaults.fullName,
      email ? defaults.email,
      timeZone ? defaults.timeZone or "UTC",
      updateChannel ? defaults.updateChannel or "stable",
      modules ? [ ],
      ...
    }@args:
    home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [
        self.homeModules.terminal
        {
          nixpkgs.overlays = [ self.overlays.default ];
          home.username = username;
          home.homeDirectory = "/Users/${username}";
          home.stateVersion = args.stateVersion or "25.05";
          home.sessionVariables.TZ = timeZone;

          keystone.update.channel = lib.mkDefault updateChannel;
          keystone.projects.enable = false;
          keystone.terminal = {
            enable = true;
            ai.enable = false;
            sandbox.enable = false;
            git = {
              userName = fullName;
              userEmail = email;
            };
          };
        }
        (args.config or { })
      ]
      ++ (defaults.modules or [ ])
      ++ modules;
    };

  mkZfsDataPoolModule =
    {
      name,
      mode,
      devices,
      datasets ? {
        bulk = {
          type = "zfs_fs";
          mountpoint = "/${name}/bulk";
        };
      },
      rootFsOptions ? {
        mountpoint = "none";
      },
      options ? {
        ashift = "12";
      },
    }:
    {
      disko.devices.disk = lib.listToAttrs (
        lib.imap0 (
          index: device:
          lib.nameValuePair "data${toString (index + 1)}" {
            type = "disk";
            inherit device;
            content = {
              type = "zfs";
              pool = name;
            };
          }
        ) devices
      );

      disko.devices.zpool.${name} = {
        type = "zpool";
        inherit
          mode
          datasets
          rootFsOptions
          options
          ;
      };
    };

  resolveOptionalPath = path: if path != null && builtins.pathExists path then path else null;

  normalizeHardwareSpec =
    spec:
    if spec == null then
      { }
    else
      let
        imported = if builtins.typeOf spec == "path" then import spec else spec;
      in
      if builtins.isFunction imported then
        { module = imported; }
      else if imported ? module then
        imported
      else
        { module = imported; };

  normalizeModuleSpec =
    spec:
    if spec == null then
      null
    else if builtins.typeOf spec == "path" then
      import spec
    else
      spec;

  # Build an installer ISO with a plain live shell, SSH access, and the
  # Keystone installer entrypoint. The ISO embeds the config repo and target
  # metadata so `ks install` can prompt for which host to install.
  mkInstallerIsoForFlake =
    {
      system ? "x86_64-linux",
      sshKeys ? [ ],
      installedSshKeys ? [ ],
      adminUsername ? "keystone",
      repoOwner ? adminUsername,
      adminName ? "System Administrator",
      adminEmail ? "admin@example.com",
      hostname ? "keystone",
      repoPath ? null,
      repoName ? "keystone-config",
      installerTargets ? { },
      devMode ? false,
    }:
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        self.nixosModules.isoInstaller
        self.nixosModules.experimental
        (
          { pkgs, ... }:
          let
            installerRepoExtraIgnores = [
              "result"
              "result-*"
              "installer-iso"
              ".test-iso*"
              "*.iso"
              ".direnv/"
              ".vscode/"
              ".gemini/"
              "*.swp"
              "*.swo"
              "*~"
              ".DS_Store"
              "Thumbs.db"
            ];

            repoSource =
              if repoPath == null then
                null
              else
                # Do not import the raw repo root with builtins.path.
                #
                # That eagerly copies every reachable file into the store before
                # the installer snapshot logic runs, including large ignored VM
                # artifacts like .test-iso-disk.raw. In practice that makes
                # dev-mode ISO builds traverse local QEMU disks and other junk
                # that should never be embedded in the live image.
                #
                # Instead, snapshot a gitignore-filtered working tree up front,
                # then synthesize a fresh single-commit repo below for the ISO.
                # gitignoreSource also loads repoPath/.gitignore automatically,
                # so generated template repos keep their shared ignore rules
                # while these extra patterns cover transient local build output.
                pkgs.nix-gitignore.gitignoreSource installerRepoExtraIgnores repoPath;

            installRepo =
              if repoSource == null then
                null
              else
                pkgs.runCommand "${repoName}-installer-repo"
                  {
                    nativeBuildInputs = with pkgs; [
                      coreutils
                      git
                      gnutar
                    ];
                  }
                  ''
                    set -euo pipefail

                    src="${repoSource}"
                    snapshot="$TMPDIR/${repoName}"

                    mkdir -p "$snapshot"
                    cp -a "$src"/. "$snapshot"/
                    chmod -R u+w "$snapshot"

                    git -C "$snapshot" init -b main
                    git -C "$snapshot" config user.name "Keystone Installer"
                    git -C "$snapshot" config user.email "installer@keystone.local"
                    git -C "$snapshot" add -A
                    GIT_AUTHOR_DATE="1980-01-01T00:00:00Z" \
                    GIT_COMMITTER_DATE="1980-01-01T00:00:00Z" \
                      git -C "$snapshot" commit -m "installer snapshot"

                    mv "$snapshot" "$out"
                  '';
          in
          {
            # Force kernel 6.12 — must override minimal CD default
            boot.kernelPackages = lib.mkForce nixpkgs.legacyPackages.${system}.linuxPackages_6_12;

            # Admin user alongside the default "nixos" user from installation-device.nix
            users.users.${adminUsername} = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "networkmanager"
                "video"
              ];
              initialHashedPassword = "";
              openssh.authorizedKeys.keys = sshKeys;
              shell = pkgs.zsh;
            };

            # Make the live installer hostname deterministic.
            networking.hostName = lib.mkForce hostname;

            # Auto-login as admin instead of "nixos"
            services.getty.autologinUser = lib.mkForce adminUsername;
            services.getty.helpLine = lib.mkForce "";
            services.getty.greetingLine = lib.mkForce "";
            nix.settings.trusted-users = [
              "root"
              adminUsername
            ];
            # Keep the live session on the admin account, but let the
            # installer re-exec as root without an interactive sudo prompt.
            security.sudo.enable = lib.mkForce true;
            security.sudo.wheelNeedsPassword = lib.mkForce false;
            programs.zsh.enable = true;

            keystone.installer.sshKeys = sshKeys;
            # TUI is experimental — default off, auto-enabled by keystone.experimental
            keystone.installer.tui.enable = lib.mkDefault false;
            nixpkgs.overlays = [ self.overlays.default ];
            environment.etc = lib.mkIf (installRepo != null) (
              {
                "keystone/install-repo".source = installRepo;
                "keystone/install-keystone".source = self.outPath;
                "keystone/install-metadata/admin-username".text = "${adminUsername}\n";
                "keystone/install-metadata/repo-owner".text = "${repoOwner}\n";
                "keystone/install-metadata/repo-name".text = "${repoName}\n";
                "keystone/install-metadata/targets.json".text = builtins.toJSON installerTargets;
              }
              // lib.optionalAttrs (installedSshKeys != [ ]) {
                "keystone/install-metadata/installed-ssh-keys".text =
                  "${lib.concatStringsSep "\n" installedSshKeys}\n";
              }
            );

            # Plain first-login bootstrap for the live installer user.
            systemd.services.installer-admin-zshrc = {
              description = "Create minimal zshrc for installer admin user";
              wantedBy = [ "multi-user.target" ];
              before = [ "getty@tty1.service" ];
              after = [
                "systemd-tmpfiles-setup.service"
                "local-fs.target"
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                                homeDir="/home/${adminUsername}"
                                zshrc="$homeDir/.zshrc"
                                mkdir -p "$homeDir"
                                chown ${adminUsername}:users "$homeDir"
                                chmod 0700 "$homeDir"

                                cat > "$zshrc" <<'EOF'
                # Minimal Keystone installer bootstrap zshrc.

                tty_path="$(tty 2>/dev/null || true)"

                if [[ "$tty_path" == "/dev/tty1" || "''${TERM:-}" == "linux" ]]; then
                  ${pkgs.util-linux}/bin/setterm --clear all --cursor on > /dev/tty1 2>/dev/null || true
                  clear >/dev/null 2>&1 || true
                  echo 'Keystone installer live environment'
                  echo 'Run `ks install` to choose a host from the embedded repo and install it.'
                  echo 'SSH is available if keys were embedded in the ISO.'
                  print
                  PROMPT='%n@%m:%~ %# '
                else
                  PROMPT='%n@%m:%~ %# '
                fi
                EOF
                                chown ${adminUsername}:users "$zshrc"
                                chmod 0644 "$zshrc"
              '';
            };
            users.users.root.shell = pkgs.bashInteractive;
          }
        )
      ];
    }).config.system.build.isoImage;

in
rec {
  mkHost = mkLinuxHost;
  mkSharedLinuxHost = mkSharedLinuxHostHelper;
  mkSharedMacosHome = mkSharedMacosHomeHelper;
  inherit mkInstallerIsoForFlake;

  # Build a bootable qcow2 disk image directly from a NixOS host configuration.
  #
  # Uses disko's image builder to partition and format a virtual disk, then
  # copies the NixOS store closure into it — no ISO or installer required.
  #
  # Usage:
  #   packages.x86_64-linux.vm-image-laptop = keystone.lib.mkVMImage {
  #     nixosSystem = nixosConfigurations.laptop;
  #   };
  #
  # The resulting derivation contains one qcow2 file per disko disk (e.g.
  # disk0.qcow2 for ZFS configs, root.qcow2 for ext4 configs).  Boot it with:
  #
  #   bin/virtual-machine --disk-path result/disk0.qcow2 --start test-vm
  #
  # Storage devices are automatically remapped to /dev/vda, /dev/vdb, … by
  # disko's image builder; no hardware paths need to be set in the config.
  mkVMImage =
    {
      # A nixpkgs.lib.nixosSystem result, e.g. nixosConfigurations.laptop.
      nixosSystem,
      # Disk devices to use inside the builder VM.  Disko's prepareDiskoConfig
      # remaps these to /dev/vda, /dev/vdb, … automatically; passing virtual
      # paths here ensures the NixOS initrd config (ZFS devNodes, LUKS device
      # references) is also consistent with the image layout.  When null
      # (default), one /dev/vd{a,b,c,…} path is generated per declared disk so
      # multi-disk storage modes (mirror/raidz) keep passing their minimum
      # device-count assertions.
      devices ? null,
      # Output image format.  qcow2 supports snapshots; raw is faster to write.
      imageFormat ? "qcow2",
      # RAM (MB) for the ephemeral QEMU builder VM.  ZFS needs more than the
      # disko default of 1024 MB; 4096 is sufficient for a single-disk pool.
      memSize ? 4096,
      # Size (disko string, e.g. "32G") of each builder VM disk.  Disko
      # defaults to 2G, which cannot hold the typical keystone layout
      # (ESP + 8G swap + root closure).  32G fits a full desktop host;
      # qcow2 is sparse, so the on-disk footprint is only what's written.
      imageSize ? "32G",
      # Additional NixOS modules applied only during image build (not at
      # runtime).  Use to inject test SSH keys, disable TPM assertions, etc.
      extraConfig ? { },
    }:
    let
      # Read disk attribute names from the un-extended config.  Reading
      # config.disko.devices.disk from inside a module that also defines
      # it would be an infinite recursion (the attrset's keys would
      # depend on the definition we're adding).  The logical disk names
      # in storage.nix don't change when we override devices, so this
      # is safe.
      diskNames = lib.attrNames nixosSystem.config.disko.devices.disk;

      # Default one virtual path per declared disk (/dev/vda, /dev/vdb, …).
      # Preserving the device-count matters for mirror/raidz hosts where
      # keystone.os.storage asserts a minimum number of devices.
      effectiveDevices =
        if devices != null then
          devices
        else
          let
            letters = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz";
          in
          lib.genList (i: "/dev/vd${builtins.elemAt letters i}") (builtins.length diskNames);

      extendedSystem = nixosSystem.extendModules {
        modules = [
          {
            # Override storage devices with virtual paths for the builder VM.
            # This fixes ZFS devNodes, LUKS crypttab references, and any other
            # initrd config that derives from keystone.os.storage.devices.
            keystone.os.storage.devices = lib.mkForce effectiveDevices;
            # Produce a qcow2 (disko defaults to raw).
            disko.imageBuilder.imageFormat = lib.mkDefault imageFormat;
            # Always include the Nix store so the image can boot standalone.
            disko.imageBuilder.copyNixStore = lib.mkDefault true;
            # Give the builder VM enough RAM for ZFS pool creation.
            disko.memSize = lib.mkDefault memSize;
            # Size every declared disk for the image builder.  Disko defaults
            # to 2G which cannot fit the typical keystone layout (ESP + swap
            # + root closure).  Only the imageSize attribute is overridden;
            # other per-disk config is preserved by module merging.
            disko.devices.disk = lib.genAttrs diskNames (_: {
              imageSize = lib.mkForce imageSize;
            });
            # Expose the initrd LUKS passphrase prompt (and any other early
            # /dev/console output) on serial.  Without this, cryptsetup-ask
            # -password only draws on VGA — a headless caller has no way to
            # type the passphrase and the VM hangs forever in initrd.
            # ttyS0 is listed last so it wins /dev/console for userspace
            # prompts; tty0 is kept so an interactive GUI caller also sees
            # the prompt.
            boot.kernelParams = [
              "console=tty0"
              "console=ttyS0,115200"
            ];
          }
          extraConfig
        ];
      };
    in
    extendedSystem.config.system.build.diskoImages;

  mkLaptop =
    {
      storage ? { },
      desktop ? true,
      ...
    }@args:
    mkLinuxHost (
      args
      // {
        inherit desktop;
        admin = if desktop then withDesktopUser args.admin else args.admin;
        storage = lib.recursiveUpdate {
          type = "ext4";
          mode = "single";
        } storage;
      }
    );

  mkWorkstation =
    {
      storage ? { },
      desktop ? true,
      ...
    }@args:
    let
      effectiveSystem = args.system or "x86_64-linux";
    in
    mkLinuxHost (
      args
      // {
        inherit desktop;
        admin = if desktop then withDesktopUser args.admin else args.admin;
        storage = lib.recursiveUpdate {
          type = "zfs";
          mode = "single";
          # The template ZFS archetypes should evaluate cleanly out of the box.
          # Pin a known-good kernel until Keystone's broader ZFS default changes.
          zfs.kernel = nixpkgs.legacyPackages.${effectiveSystem}.linuxPackages_6_12;
        } storage;
      }
    );

  mkServer =
    {
      storage ? { },
      dataPool ? null,
      desktop ? false,
      modules ? [ ],
      ...
    }@args:
    let
      effectiveSystem = args.system or "x86_64-linux";
    in
    mkLinuxHost (
      (builtins.removeAttrs args [
        "dataPool"
        "modules"
      ])
      // {
        inherit desktop;
        storage = lib.recursiveUpdate {
          type = "zfs";
          mode = "single";
          # The template ZFS archetypes should evaluate cleanly out of the box.
          # Pin a known-good kernel until Keystone's broader ZFS default changes.
          zfs.kernel = nixpkgs.legacyPackages.${effectiveSystem}.linuxPackages_6_12;
        } storage;
        modules =
          modules
          ++ lib.optional (dataPool != null) (mkZfsDataPoolModule {
            name = dataPool.name or "ocean";
            mode = dataPool.mode;
            devices = dataPool.devices;
            datasets =
              dataPool.datasets or {
                bulk = {
                  type = "zfs_fs";
                  mountpoint = "/${dataPool.name or "ocean"}/bulk";
                };
              };
          });
      }
    );

  mkMacosTerminal =
    {
      system ? "aarch64-darwin",
      username,
      fullName,
      email,
      stateVersion ? "25.05",
      config ? { },
      modules ? [ ],
    }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [
        self.homeModules.terminal
        {
          nixpkgs.overlays = [ self.overlays.default ];
          home.username = username;
          home.homeDirectory = "/Users/${username}";
          home.stateVersion = stateVersion;

          keystone.projects.enable = false;
          keystone.terminal = {
            enable = true;
            ai.enable = false;
            sandbox.enable = false;
            git = {
              userName = fullName;
              userEmail = email;
            };
          };
        }
        config
      ]
      ++ modules;
    };

  mkZfsDataPool = mkZfsDataPoolModule;

  mkSystemFlake =
    {
      admin,
      repoOwner ? null,
      repoName ? "keystone-config",
      defaults ? { },
      shared ? { },
      hostsRoot ? null,
      repoRoot ? null,
      keystoneServices ? { },
      hosts,
    }:
    let
      linuxKindDefaults = {
        laptop = {
          builder = mkLaptop;
          system = "x86_64-linux";
          nixosModules = [ ];
          desktop = true;
        };

        workstation = {
          builder = mkWorkstation;
          system = "x86_64-linux";
          nixosModules = [ ];
          desktop = true;
        };

        server = {
          builder = mkServer;
          system = "x86_64-linux";
          nixosModules = [ self.nixosModules.server ];
          desktop = false;
        };
      };

      darwinKindDefaults = {
        macbook = {
          system = defaults.darwinSystem or "aarch64-darwin";
        };
      };

      # admin is the single source of truth — strip template-only fields
      # (sshKeys) to produce a valid userSubmodule config.
      # username is passed through to keystone.os.adminUsername.
      adminUsername = admin.username or "keystone";
      effectiveRepoOwner = if repoOwner != null then repoOwner else adminUsername;
      adminSshKeys = admin.sshKeys or [ ];
      sharedAdmin = builtins.removeAttrs admin [
        "username"
        "sshKeys"
      ];
      sharedUsers = shared.users or { };
      # NixOS modules applied OS-wide on every host.
      sharedSystemModules = shared.systemModules or [ ];
      # Home Manager modules applied per-user on every host.
      sharedUserModules = shared.userModules or [ ];
      # Home Manager modules applied per-user on desktop hosts (laptop, workstation) only.
      sharedDesktopUserModules = shared.desktopUserModules or [ ];
      # specialArgs forwarded to every Linux host's nixosSystem call.
      # Use this to provide module function args like `inputs`, `self`,
      # `outputs` that consumer modules consume via the
      # `{ inputs, ... }: { imports = [ inputs.X ]; ... }` pattern. These
      # args must be visible at module-import time, which `_module.args`
      # cannot satisfy without infinite recursion. Per-host
      # `hosts.<name>.specialArgs` are merged on top of `shared.specialArgs`
      # via shallow last-write-wins (`sharedSpecialArgs // hostSpecialArgs`),
      # so a host entry replaces the fleet value for any key it sets.
      sharedSpecialArgs = shared.specialArgs or { };
      sharedTimeZone = defaults.timeZone or "UTC";
      sharedUpdateChannel = defaults.updateChannel or "stable";
      effectiveRepoRoot =
        if repoRoot != null then
          repoRoot
        else if hostsRoot != null then
          builtins.dirOf hostsRoot
        else
          null;
      repoRootString = if effectiveRepoRoot == null then null else toString effectiveRepoRoot;

      hostFilePath =
        name: file:
        if hostsRoot == null then null else resolveOptionalPath (hostsRoot + "/${name}/${file}");

      relativeRepoPath =
        path:
        if path == null || repoRootString == null then
          null
        else
          let
            pathString = toString path;
            prefix = "${repoRootString}/";
          in
          if lib.hasPrefix prefix pathString then lib.removePrefix prefix pathString else null;

      linuxKindDefaultsFor =
        hostCfg:
        if builtins.hasAttr hostCfg.kind linuxKindDefaults then
          linuxKindDefaults.${hostCfg.kind}
        else
          throw "Unsupported Keystone Linux host kind `${hostCfg.kind}`.";

      linuxHardwarePathFor =
        name: hostCfg: if hostCfg ? hardware then hostCfg.hardware else hostFilePath name "hardware.nix";

      linuxHardwareSpecFor =
        name: hostCfg:
        let
          hardwarePath = linuxHardwarePathFor name hostCfg;
        in
        if hardwarePath == null then { } else normalizeHardwareSpec hardwarePath;

      linuxHostSystemFor =
        name: hostCfg:
        let
          kindDefaults = linuxKindDefaultsFor hostCfg;
          hardwareSpec = linuxHardwareSpecFor name hostCfg;
        in
        if hostCfg ? system then
          hostCfg.system
        else if hardwareSpec ? system then
          hardwareSpec.system
        else
          kindDefaults.system;

      mkLinuxInstallerTarget =
        name: hostCfg:
        let
          hardwarePath = linuxHardwarePathFor name hostCfg;
          relativeHardwarePath = relativeRepoPath hardwarePath;
          storageType =
            if hostCfg ? storage && hostCfg.storage ? type then
              hostCfg.storage.type
            else if hostCfg.kind == "laptop" then
              "ext4"
            else
              "zfs";
        in
        lib.optionalAttrs (relativeHardwarePath != null) {
          flakeHost = name;
          hostname = hostCfg.hostname or name;
          system = linuxHostSystemFor name hostCfg;
          inherit storageType;
          hardwarePath = relativeHardwarePath;
        };

      mkLinuxInventoryHost =
        name: hostCfg:
        let
          kindDefaults = linuxKindDefaultsFor hostCfg;
          hardwarePath = linuxHardwarePathFor name hostCfg;
          hardwareSpec = linuxHardwareSpecFor name hostCfg;
          configurationPath =
            if hostCfg ? configuration then hostCfg.configuration else hostFilePath name "configuration.nix";
          mergedConfig = lib.recursiveUpdate (hostCfg.config or { }) (
            lib.optionalAttrs (hostCfg ? services) {
              services = hostCfg.services;
            }
          );
          modules =
            (lib.optional (hardwareSpec ? module) hardwareSpec.module)
            ++ (lib.optional (configurationPath != null) (normalizeModuleSpec configurationPath))
            ++ (hostCfg.modules or [ ]);
          hostUpdateChannel = if hostCfg ? updateChannel then hostCfg.updateChannel else sharedUpdateChannel;
          builderArgs =
            (builtins.removeAttrs hostCfg [
              "kind"
              "hardware"
              "configuration"
              "services"
              "config"
              "modules"
              "updateChannel"
              "specialArgs"
            ])
            // {
              hostname = hostCfg.hostname or name;
              system = linuxHostSystemFor name hostCfg;
              timeZone = if hostCfg ? timeZone then hostCfg.timeZone else sharedTimeZone;
              admin = if hostCfg ? admin then hostCfg.admin else sharedAdmin;
              inherit adminUsername;
              users = sharedUsers // (hostCfg.users or { });
              nixosModules = kindDefaults.nixosModules ++ (hostCfg.nixosModules or [ ]);
              # Shallow last-write-wins merge: per-host `specialArgs` keys
              # replace identical keys from `shared.specialArgs`. Nested
              # values are not merged — set the full nested structure on
              # the host if you need to override a sub-key.
              specialArgs = sharedSpecialArgs // (hostCfg.specialArgs or { });
              config = lib.recursiveUpdate mergedConfig {
                keystone.services = keystoneServices;
                keystone.update.channel = lib.mkDefault hostUpdateChannel;
              };
              modules = [
                {
                  # NixOS and home-manager have separate option trees. The
                  # `config` block above sets keystone.update.channel at the
                  # NixOS level, but the Walker `ks-update.service` and the
                  # terminal `KS_UPDATE_CHANNEL` sessionVariable are declared
                  # in home-manager modules reading home-manager's config. A
                  # sharedModules entry bridges the same value across, so
                  # unit Environment and user shell agree on the channel.
                  home-manager.sharedModules =
                    sharedUserModules
                    ++ lib.optionals kindDefaults.desktop sharedDesktopUserModules
                    ++ [
                      {
                        keystone.update.channel = lib.mkDefault hostUpdateChannel;
                      }
                    ];
                }
              ]
              ++ lib.optional (adminSshKeys != [ ]) {
                # Bridge admin.sshKeys to installed hosts so the keys survive
                # NixOS system activation (which overwrites ~/.ssh/authorized_keys).
                users.users.${adminUsername}.openssh.authorizedKeys.keys = adminSshKeys;
              }
              ++ sharedSystemModules
              ++ modules;
            };
        in
        kindDefaults.builder builderArgs;

      mkDarwinInventoryHost =
        name: hostCfg:
        let
          kindDefaults =
            if builtins.hasAttr hostCfg.kind darwinKindDefaults then
              darwinKindDefaults.${hostCfg.kind}
            else
              throw "Unsupported Keystone macOS host kind `${hostCfg.kind}`.";
          configurationPath =
            if hostCfg ? configuration then hostCfg.configuration else hostFilePath name "configuration.nix";
          modules =
            (lib.optional (configurationPath != null) (normalizeModuleSpec configurationPath))
            ++ (hostCfg.modules or [ ]);
          builderArgs =
            (builtins.removeAttrs hostCfg [
              "kind"
              "configuration"
              "modules"
              "updateChannel"
            ])
            // {
              system = if hostCfg ? system then hostCfg.system else kindDefaults.system;
              username = if hostCfg ? username then hostCfg.username else adminUsername;
              fullName = if hostCfg ? fullName then hostCfg.fullName else sharedAdmin.fullName;
              email = if hostCfg ? email then hostCfg.email else sharedAdmin.email;
              timeZone = if hostCfg ? timeZone then hostCfg.timeZone else sharedTimeZone;
              updateChannel = if hostCfg ? updateChannel then hostCfg.updateChannel else sharedUpdateChannel;
              modules = sharedUserModules ++ modules;
            };
        in
        (mkSharedMacosHome { }) builderArgs;

      linuxHosts = lib.filterAttrs (_: hostCfg: builtins.hasAttr hostCfg.kind linuxKindDefaults) hosts;
      darwinHosts = lib.filterAttrs (_: hostCfg: builtins.hasAttr hostCfg.kind darwinKindDefaults) hosts;
      linuxHostSystems = lib.unique (lib.mapAttrsToList linuxHostSystemFor linuxHosts);
      installerSystem =
        if linuxHostSystems == [ ] then
          defaults.system or null
        else if lib.length linuxHostSystems > 1 then
          throw ''
            mkSystemFlake exposes a single installer ISO output, but the Linux host inventory uses multiple systems: ${lib.concatStringsSep ", " linuxHostSystems}.
            Split those hosts into separate flakes or make their Linux systems agree before building one shared installer ISO.
          ''
        else
          let
            detectedSystem = builtins.head linuxHostSystems;
          in
          if defaults ? system && defaults.system != detectedSystem then
            throw ''
              mkSystemFlake defaults.system (${defaults.system}) does not match the detected Linux host system (${detectedSystem}).
              Remove defaults.system or update it to match the Linux host inventory before building the installer ISO.
            ''
          else
            detectedSystem;
      installerTargets = lib.filterAttrs (_: target: target != { }) (
        lib.mapAttrs mkLinuxInstallerTarget linuxHosts
      );
    in
    {
      nixosConfigurations = lib.mapAttrs mkLinuxInventoryHost linuxHosts;
      homeConfigurations = lib.mapAttrs mkDarwinInventoryHost darwinHosts;
      inherit installerTargets;
      # Expose admin identity so tooling (e.g. bin/test-iso) can read it without
      # parsing flake.nix directly.
      inherit adminUsername;
      adminEmail = sharedAdmin.email;
      adminName = sharedAdmin.fullName;
    }
    // lib.optionalAttrs (installerSystem != null) {
      packages.${installerSystem} =
        let
          pkgs = nixpkgs.legacyPackages.${installerSystem};
          # Build vm-image-<name> for every Linux host whose architecture
          # matches the installer system (avoids cross-compilation failures).
          # Filter first to avoid evaluating configs for hosts that won't be packaged.
          vmImageHosts = lib.filterAttrs (
            name: _: linuxHostSystemFor name linuxHosts.${name} == installerSystem
          ) linuxHosts;
          linuxHostConfigurations = lib.mapAttrs mkLinuxInventoryHost vmImageHosts;
          vmImagePackages = lib.mapAttrs' (
            name: _:
            lib.nameValuePair "vm-image-${name}" (mkVMImage {
              nixosSystem = linuxHostConfigurations.${name};
            })
          ) vmImageHosts;
        in
        {
          installerTargetsJson = pkgs.writeText "installer-targets.json" (builtins.toJSON installerTargets);
          iso = mkInstallerIsoForFlake {
            system = installerSystem;
            sshKeys = adminSshKeys;
            inherit
              adminUsername
              installerTargets
              ;
            adminName = sharedAdmin.fullName;
            adminEmail = sharedAdmin.email;
            repoPath = effectiveRepoRoot;
            repoOwner = effectiveRepoOwner;
            # Use an explicit repo name instead of deriving it from the flake
            # evaluation path. During `nix build`, the repo root often resolves
            # to a store-style `...-source` path, which would leak that hash
            # into the installed config handoff.
            inherit repoName;
          };
        }
        // vmImagePackages;
    };
}
