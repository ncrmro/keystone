{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  home-manager ? null,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  hmLib = if home-manager != null then home-manager.lib else null;

  mkTemplateConfig =
    {
      hostname,
      hostId,
      storageType,
      storageDevices,
      storageMode ? "single",
      swapSize ? "16G",
      hibernateEnable ? false,
      secureBootEnable ? true,
      tpmEnable ? true,
      remoteUnlockEnable ? false,
      remoteUnlockAuthorizedKeys ? [ ],
      sshEnable ? true,
      users,
      timeZone ? "UTC",
      stateVersion ? "25.05",
      desktopEnable ? false,
      extraModules ? [ ],
    }:
    [
      self.nixosModules.operating-system
    ]
    ++ [
      {
        networking.hostName = hostname;
        networking.hostId = hostId;
        system.stateVersion = stateVersion;
        time.timeZone = timeZone;
        boot.loader.systemd-boot.enable = true;

        keystone.os = {
          enable = true;
          storage = {
            type = storageType;
            devices = storageDevices;
            mode = storageMode;
            swap.size = swapSize;
          }
          // lib.optionalAttrs (storageType == "ext4" && hibernateEnable) { hibernate.enable = true; };
          secureBoot.enable = secureBootEnable;
          tpm.enable = tpmEnable;
          ssh.enable = sshEnable;
          remoteUnlock = lib.mkIf remoteUnlockEnable {
            enable = true;
            authorizedKeys = remoteUnlockAuthorizedKeys;
          };
          inherit users;
        };

        fileSystems."/" = {
          device = if storageType == "zfs" then lib.mkForce "rpool/root" else lib.mkForce "/dev/vda2";
          fsType = lib.mkForce (if storageType == "zfs" then "zfs" else "ext4");
        };

        nix.settings.trusted-users = [
          "root"
          "@wheel"
        ];
      }
    ]
    ++ lib.optionals desktopEnable [ self.nixosModules.desktop ]
    ++ extraModules;

  evalNixos =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      };
      usersJson = builtins.toJSON (builtins.attrNames result.config.users.users);
      groupsJson = builtins.toJSON (builtins.attrNames result.config.users.groups);
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
      desktopUserJson = builtins.toJSON (result.config.keystone.desktop.user or null);
      primaryUser = builtins.head (builtins.attrNames result.config.users.users);
      primaryGroupsJson = builtins.toJSON result.config.users.users.${primaryUser}.extraGroups;
    in
    pkgs.runCommand "eval-template-${name}" { } ''
      mkdir -p $out
      cat > $out/${name}.json <<'ENDJSON'
      {
        "name": "${name}",
        "kind": "nixos",
        "users": ${usersJson},
        "groups": ${groupsJson},
        "services": ${servicesJson},
        "desktopUser": ${desktopUserJson},
        "primaryUserGroups": ${primaryGroupsJson}
      }
      ENDJSON
    '';

  evalHome =
    name:
    {
      system,
      username,
      fullName,
      email,
      stateVersion ? "25.05",
    }:
    let
      hmConfig = hmLib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [
          self.homeModules.terminal
          {
            nixpkgs.overlays = [ self.overlays.default ];
            home.username = username;
            home.homeDirectory =
              if lib.hasSuffix "-darwin" system then "/Users/${username}" else "/home/${username}";
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
        ];
      };
      homeFileKeysJson = builtins.toJSON (builtins.attrNames hmConfig.config.home.file);
      gitEnabledJson = builtins.toJSON hmConfig.config.programs.git.enable;
      homeDirJson = builtins.toJSON hmConfig.config.home.homeDirectory;
    in
    pkgs.runCommand "eval-template-${name}" { } ''
      mkdir -p $out
      cat > $out/${name}.json <<'ENDJSON'
      {
        "name": "${name}",
        "kind": "home-manager",
        "gitEnabled": ${gitEnabledJson},
        "homeDirectory": ${homeDirJson},
        "homeFileKeys": ${homeFileKeysJson}
      }
      ENDJSON
    '';

  nixosTests = {
    laptop-ext4 = evalNixos "laptop-ext4" (mkTemplateConfig {
      hostname = "laptop";
      hostId = "55667788";
      storageType = "ext4";
      storageDevices = [ "/dev/disk/by-id/nvme-laptop-root-001" ];
      desktopEnable = true;
      users.admin = {
        fullName = "Laptop User";
        email = "laptop@example.com";
        extraGroups = [ "wheel" ];
        initialPassword = "changeme";
        terminal.enable = true;
        desktop.enable = true;
      };
    });

    workstation-zfs-single = evalNixos "workstation-zfs-single" (mkTemplateConfig {
      hostname = "workstation";
      hostId = "aabbccdd";
      storageType = "zfs";
      storageDevices = [ "/dev/disk/by-id/nvme-workstation-root-001" ];
      desktopEnable = true;
      users.admin = {
        fullName = "Workstation User";
        email = "workstation@example.com";
        extraGroups = [ "wheel" ];
        initialPassword = "changeme";
        terminal.enable = true;
        desktop = {
          enable = true;
          hyprland.modifierKey = "SUPER";
        };
      };
    });

    workstation-zfs-mirror = evalNixos "workstation-zfs-mirror" (mkTemplateConfig {
      hostname = "workstation-mirror";
      hostId = "11223344";
      storageType = "zfs";
      storageDevices = [
        "/dev/disk/by-id/nvme-workstation-root-001"
        "/dev/disk/by-id/nvme-workstation-root-002"
      ];
      storageMode = "mirror";
      desktopEnable = true;
      users.admin = {
        fullName = "Workstation User";
        email = "workstation@example.com";
        extraGroups = [ "wheel" ];
        initialPassword = "changeme";
        terminal.enable = true;
        desktop = {
          enable = true;
          hyprland.modifierKey = "SUPER";
        };
      };
    });

    nas-zfs-root-plus-raidz2 = evalNixos "nas-zfs-root-plus-raidz2" (mkTemplateConfig {
      hostname = "nas";
      hostId = "99aabbcc";
      storageType = "zfs";
      storageDevices = [ "/dev/disk/by-id/nvme-nas-root-001" ];
      users.admin = {
        fullName = "NAS Admin";
        email = "nas@example.com";
        extraGroups = [ "wheel" ];
        initialPassword = "changeme";
        terminal.enable = true;
      };
      extraModules = [
        {
          disko.devices.disk.data1 = {
            type = "disk";
            device = "/dev/disk/by-id/hdd-nas-data-001";
            content = {
              type = "zfs";
              pool = "ocean";
            };
          };
          disko.devices.disk.data2 = {
            type = "disk";
            device = "/dev/disk/by-id/hdd-nas-data-002";
            content = {
              type = "zfs";
              pool = "ocean";
            };
          };
          disko.devices.disk.data3 = {
            type = "disk";
            device = "/dev/disk/by-id/hdd-nas-data-003";
            content = {
              type = "zfs";
              pool = "ocean";
            };
          };
          disko.devices.disk.data4 = {
            type = "disk";
            device = "/dev/disk/by-id/hdd-nas-data-004";
            content = {
              type = "zfs";
              pool = "ocean";
            };
          };
          disko.devices.disk.data5 = {
            type = "disk";
            device = "/dev/disk/by-id/hdd-nas-data-005";
            content = {
              type = "zfs";
              pool = "ocean";
            };
          };
          disko.devices.zpool.ocean = {
            type = "zpool";
            mode = "raidz2";
            rootFsOptions.mountpoint = "none";
            options.ashift = "12";
            datasets.bulk = {
              type = "zfs_fs";
              mountpoint = "/ocean/bulk";
            };
          };
        }
      ];
    });
  };

  homeTests = lib.optionalAttrs (hmLib != null) {
    macos-terminal-only = evalHome "macos-terminal-only" {
      system = "aarch64-darwin";
      username = "testuser";
      fullName = "Mac User";
      email = "mac@example.com";
    };
  };

  tests = nixosTests // homeTests;
in
pkgs.runCommand "test-template-evaluation"
  {
    buildInputs = builtins.attrValues tests;
  }
  ''
    mkdir -p $out
    echo "Template archetype evaluation tests"
    echo "================================="
    echo ""
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: drv: ''
        cp ${drv}/${name}.json $out/${name}.json
      '') tests
    )}
    echo "All template archetypes evaluated successfully!"
    echo ""
    echo "Inspect output: cat result/<config-name>.json"
    echo "Configs: ${lib.concatStringsSep ", " (builtins.attrNames tests)}"
  ''
