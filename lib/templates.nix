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
    {
      networking.hostName = hostname;
      system.stateVersion = stateVersion;
      time.timeZone = timeZone;
      boot.loader.systemd-boot.enable = lib.mkDefault true;

      keystone.os = {
        enable = true;
        inherit
          admin
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
    }
    // config;

  mkLinuxHost =
    {
      system ? "x86_64-linux",
      hostname,
      stateVersion ? "25.05",
      timeZone ? "UTC",
      storage,
      admin,
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
  # starship), SSH keys for remote access, and the TUI installer.
  # self.homeModules.terminal already embeds keystoneInputs via _module.args,
  # so we don't need the full keystoneInputs attrset here.
  mkInstallerIsoForFlake =
    {
      system ? "x86_64-linux",
      sshKeys ? [ ],
      adminName ? "System Administrator",
      adminEmail ? "admin@example.com",
    }:
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        self.nixosModules.isoInstaller
        home-manager.nixosModules.home-manager
        {
          # Force kernel 6.12 — must override minimal CD default
          boot.kernelPackages = lib.mkForce nixpkgs.legacyPackages.${system}.linuxPackages_6_12;

          keystone.installer.sshKeys = sshKeys;
          nixpkgs.overlays = [ self.overlays.default ];

          # Terminal environment for root user (helix, zsh, starship)
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.root = {
            imports = [ self.homeModules.terminal ];
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
          };
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
      owner,
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

      sharedAdmin =
        shared.admin or {
          fullName = owner.name;
          email = owner.email or "admin@example.com";
          initialPassword = "changeme";
        };
      sharedUsers = shared.users or { };
      sharedSystemModules = shared.systemModules or [ ];
      sharedUserModules = shared.userModules or [ ];
      sharedTimeZone = defaults.timeZone or "UTC";
      defaultLinuxSystem = defaults.system or "x86_64-linux";
      ownerSshKeys = owner.sshKeys or [ ];

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
              username = if hostCfg ? username then hostCfg.username else owner.username or "admin";
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
        sshKeys = ownerSshKeys;
        adminName = sharedAdmin.fullName;
        adminEmail = sharedAdmin.email;
      };
    };
}
