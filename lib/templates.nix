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
      adminUsername ? "admin",
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
          admin
          adminUsername
          users
          storage
          secureBoot
          tpm
          ssh
          remoteUnlock
          ;
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
      adminUsername ? "admin",
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
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;
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

  # Build an installer ISO with the admin's terminal environment (helix, zsh,
  # starship) and SSH keys for remote access. Boots to the admin user on tty1.
  # TUI installer is experimental — auto-enabled only when keystone.experimental = true.
  #
  # Imports iso-image.nix + base.nix + minimal.nix directly (skipping
  # installation-device.nix which hardcodes a "nixos" user and auto-login).
  mkInstallerIsoForFlake =
    {
      system ? "x86_64-linux",
      sshKeys ? [ ],
      adminUsername ? "admin",
      adminName ? "System Administrator",
      adminEmail ? "admin@example.com",
    }:
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        # ISO image infrastructure (replaces installation-cd-minimal.nix to
        # avoid the hardcoded "nixos" user from installation-device.nix)
        "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        "${nixpkgs}/nixos/modules/profiles/base.nix"
        "${nixpkgs}/nixos/modules/profiles/minimal.nix"
        # Hardware detection and installer channel (from installation-device.nix)
        "${nixpkgs}/nixos/modules/installer/scan/detected.nix"
        "${nixpkgs}/nixos/modules/installer/scan/not-detected.nix"
        "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"

        # fileSystems must reference config.lib.isoFileSystems from inside a module
        (
          { config, ... }:
          {
            fileSystems = lib.mkImageMediaOverride config.lib.isoFileSystems;
          }
        )

        self.nixosModules.isoInstaller
        self.nixosModules.experimental
        home-manager.nixosModules.home-manager
        {
          # Force kernel 6.12
          boot.kernelPackages = lib.mkForce nixpkgs.legacyPackages.${system}.linuxPackages_6_12;

          # From installation-cd-base.nix
          hardware.enableAllHardware = true;
          isoImage.makeEfiBootable = true;
          isoImage.makeUsbBootable = true;
          isoImage.edition = lib.mkOverride 500 "minimal";
          boot.loader.grub.memtest86.enable = true;
          swapDevices = lib.mkImageMediaOverride [ ];
          boot.initrd.luks.devices = lib.mkImageMediaOverride { };
          programs.git.enable = lib.mkDefault true;
          documentation.man.enable = lib.mkOverride 500 true;
          documentation.doc.enable = lib.mkOverride 500 true;
          fonts.fontconfig.enable = lib.mkOverride 500 false;

          # Admin user (replaces the hardcoded "nixos" user)
          users.users.${adminUsername} = {
            isNormalUser = true;
            extraGroups = [
              "wheel"
              "networkmanager"
              "video"
            ];
            initialHashedPassword = "";
          };
          users.users.root.initialHashedPassword = "";

          security.polkit.enable = true;
          security.sudo = {
            enable = lib.mkDefault true;
            wheelNeedsPassword = lib.mkImageMediaOverride false;
          };

          # Auto-login as the admin user
          services.getty.autologinUser = adminUsername;
          nix.settings.trusted-users = [
            "root"
            adminUsername
          ];

          boot.swraid.enable = true;
          boot.swraid.mdadmConf = "PROGRAM ${nixpkgs.legacyPackages.${system}.coreutils}/bin/true";
          networking.firewall.logRefusedConnections = lib.mkDefault false;

          keystone.installer.sshKeys = sshKeys;
          # TUI is experimental — default off, auto-enabled by keystone.experimental
          keystone.installer.tui.enable = lib.mkDefault false;
          nixpkgs.overlays = [ self.overlays.default ];

          # Terminal environment for root and admin users (helix, zsh, starship)
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.sharedModules = [
            self.homeModules.terminal
            self.homeModules.notes
          ];
          home-manager.users.root = {
            home.stateVersion = "25.05";
            keystone.terminal = {
              enable = true;
              ai.enable = false;
              sandbox.enable = false;
              git = {
                userName = adminName;
                userEmail = adminEmail;
              };
            };
            keystone.projects.enable = false;
            keystone.notes.enable = false;
          };
          home-manager.users.${adminUsername} = {
            home.stateVersion = "25.05";
            home.username = adminUsername;
            home.homeDirectory = "/home/${adminUsername}";
            keystone.terminal = {
              enable = true;
              ai.enable = false;
              sandbox.enable = false;
              git = {
                userName = adminName;
                userEmail = adminEmail;
              };
            };
            keystone.projects.enable = false;
            keystone.notes.enable = false;
          };

          programs.zsh.enable = true;
        }
      ];
    }).config.system.build.isoImage;

in
rec {
  mkHost = mkLinuxHost;
  mkSharedLinuxHost = mkSharedLinuxHostHelper;
  mkSharedMacosHome = mkSharedMacosHomeHelper;

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
    mkLinuxHost (
      args
      // {
        inherit desktop;
        admin = if desktop then withDesktopUser args.admin else args.admin;
        storage = lib.recursiveUpdate {
          type = "zfs";
          mode = "single";
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
      defaults ? { },
      shared ? { },
      hostsRoot ? null,
      keystoneServices ? { },
      hosts,
    }:
    let
      linuxKindDefaults = {
        laptop = {
          builder = mkLaptop;
          system = "x86_64-linux";
          nixosModules = [ ];
        };

        workstation = {
          builder = mkWorkstation;
          system = "x86_64-linux";
          nixosModules = [ ];
        };

        server = {
          builder = mkServer;
          system = "x86_64-linux";
          nixosModules = [ self.nixosModules.server ];
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
      adminUsername = admin.username or "admin";
      adminSshKeys = admin.sshKeys or [ ];
      sharedAdmin = builtins.removeAttrs admin [
        "username"
        "sshKeys"
      ];
      sharedUsers = shared.users or { };
      sharedSystemModules = shared.systemModules or [ ];
      sharedUserModules = shared.userModules or [ ];
      sharedTimeZone = defaults.timeZone or "UTC";
      defaultLinuxSystem = defaults.system or "x86_64-linux";

      hostFilePath =
        name: file:
        if hostsRoot == null then null else resolveOptionalPath (hostsRoot + "/${name}/${file}");

      mkLinuxInventoryHost =
        name: hostCfg:
        let
          kindDefaults =
            if builtins.hasAttr hostCfg.kind linuxKindDefaults then
              linuxKindDefaults.${hostCfg.kind}
            else
              throw "Unsupported Keystone Linux host kind `${hostCfg.kind}`.";
          hardwarePath = if hostCfg ? hardware then hostCfg.hardware else hostFilePath name "hardware.nix";
          hardwareSpec = if hardwarePath == null then { } else normalizeHardwareSpec hardwarePath;
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
          builderArgs =
            (builtins.removeAttrs hostCfg [
              "kind"
              "hardware"
              "configuration"
              "services"
              "config"
              "modules"
            ])
            // {
              hostname = hostCfg.hostname or name;
              system =
                if hostCfg ? system then
                  hostCfg.system
                else if hardwareSpec ? system then
                  hardwareSpec.system
                else
                  kindDefaults.system;
              timeZone = if hostCfg ? timeZone then hostCfg.timeZone else sharedTimeZone;
              admin = if hostCfg ? admin then hostCfg.admin else sharedAdmin;
              inherit adminUsername;
              users = sharedUsers // (hostCfg.users or { });
              nixosModules = kindDefaults.nixosModules ++ (hostCfg.nixosModules or [ ]);
              config = lib.recursiveUpdate mergedConfig {
                keystone.services = keystoneServices;
              };
              modules = [
                {
                  home-manager.sharedModules = sharedUserModules;
                }
              ]
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
            ])
            // {
              system = if hostCfg ? system then hostCfg.system else kindDefaults.system;
              username = if hostCfg ? username then hostCfg.username else adminUsername;
              fullName = if hostCfg ? fullName then hostCfg.fullName else sharedAdmin.fullName;
              email = if hostCfg ? email then hostCfg.email else sharedAdmin.email;
              timeZone = if hostCfg ? timeZone then hostCfg.timeZone else sharedTimeZone;
              modules = sharedUserModules ++ modules;
            };
        in
        (mkSharedMacosHome { }) builderArgs;

      linuxHosts = lib.filterAttrs (_: hostCfg: builtins.hasAttr hostCfg.kind linuxKindDefaults) hosts;
      darwinHosts = lib.filterAttrs (_: hostCfg: builtins.hasAttr hostCfg.kind darwinKindDefaults) hosts;
    in
    {
      nixosConfigurations = lib.mapAttrs mkLinuxInventoryHost linuxHosts;
      homeConfigurations = lib.mapAttrs mkDarwinInventoryHost darwinHosts;
    }
    // lib.optionalAttrs (linuxHosts != { }) {
      packages.${defaultLinuxSystem}.iso = mkInstallerIsoForFlake {
        system = defaultLinuxSystem;
        sshKeys = adminSshKeys;
        inherit adminUsername;
        adminName = sharedAdmin.fullName;
        adminEmail = sharedAdmin.email;
      };
    };
}
