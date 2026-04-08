{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  home-manager ? null,
}:
let
  templateFlake = import ../../templates/default/flake.nix;
  templateOutputs = templateFlake.outputs {
    inherit nixpkgs;
    keystone = self;
  };

  evalNixos =
    name: system:
    let
      result = system.config;
      systemJson = builtins.toJSON system.pkgs.stdenv.hostPlatform.system;
      usersJson = builtins.toJSON (builtins.attrNames result.users.users);
      groupsJson = builtins.toJSON (builtins.attrNames result.users.groups);
      servicesJson = builtins.toJSON (builtins.attrNames result.systemd.services);
      primaryUser = builtins.head (builtins.attrNames result.users.users);
      primaryGroupsJson = builtins.toJSON result.users.users.${primaryUser}.extraGroups;
      fileSystemJson = builtins.toJSON (
        if result.fileSystems ? "/" then result.fileSystems."/".fsType else null
      );
      hostJson = builtins.toJSON result.networking.hostName;
    in
    pkgs.runCommand "eval-template-${name}" { } ''
      mkdir -p $out
      cat > $out/${name}.json <<'ENDJSON'
      {
        "name": "${name}",
        "kind": "nixos",
        "hostname": ${hostJson},
        "system": ${systemJson},
        "rootFsType": ${fileSystemJson},
        "users": ${usersJson},
        "groups": ${groupsJson},
        "services": ${servicesJson},
        "primaryUserGroups": ${primaryGroupsJson}
      }
      ENDJSON
    '';

  evalHome =
    name: system:
    let
      result = system.config;
      homeFileKeysJson = builtins.toJSON (builtins.attrNames result.home.file);
      gitEnabledJson = builtins.toJSON result.programs.git.enable;
      homeDirJson = builtins.toJSON result.home.homeDirectory;
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
    template-default-laptop = evalNixos "template-default-laptop" templateOutputs.nixosConfigurations.laptop;
    template-default-server-ocean = evalNixos "template-default-server-ocean" templateOutputs.nixosConfigurations.server-ocean;

    template-default-iso =
      let
        isoSystem = templateOutputs.nixosConfigurations.laptop.pkgs.stdenv.hostPlatform.system;
        isoImage = templateOutputs.packages.${isoSystem}.iso;
      in
      pkgs.runCommand "eval-template-iso" { } ''
        mkdir -p $out
        cat > $out/template-default-iso.json <<'ENDJSON'
        {
          "name": "template-default-iso",
          "kind": "iso",
          "isoName": "${isoImage.name}"
        }
        ENDJSON
      '';

    laptop-ext4 = evalNixos "laptop-ext4" (
      self.lib.mkLaptop {
        hostname = "laptop";
        admin = {
          fullName = "Laptop User";
          email = "laptop@example.com";
          initialPassword = "changeme";
          terminal.enable = true;
        };
        storage.devices = [ "/dev/disk/by-id/nvme-laptop-root-001" ];
        modules = [
          {
            networking.hostId = "55667788";
          }
        ];
      }
    );

    workstation-zfs-single = evalNixos "workstation-zfs-single" (
      self.lib.mkWorkstation {
        hostname = "workstation";
        admin = {
          fullName = "Workstation User";
          email = "workstation@example.com";
          initialPassword = "changeme";
          terminal.enable = true;
          desktop.hyprland.modifierKey = "SUPER";
        };
        storage.devices = [ "/dev/disk/by-id/nvme-workstation-root-001" ];
        modules = [
          {
            networking.hostId = "aabbccdd";
          }
        ];
      }
    );

    workstation-zfs-stripe = evalNixos "workstation-zfs-stripe" (
      self.lib.mkWorkstation {
        hostname = "workstation-stripe";
        admin = {
          fullName = "Workstation User";
          email = "workstation@example.com";
          initialPassword = "changeme";
          terminal.enable = true;
          desktop.hyprland.modifierKey = "SUPER";
        };
        storage = {
          mode = "stripe";
          devices = [
            "/dev/disk/by-id/nvme-workstation-root-001"
            "/dev/disk/by-id/nvme-workstation-root-002"
          ];
        };
        modules = [
          {
            networking.hostId = "11223344";
          }
        ];
      }
    );

    server-zfs-root-plus-raidz2 = evalNixos "server-zfs-root-plus-raidz2" (
      self.lib.mkServer {
        hostname = "server";
        admin = {
          fullName = "Server Admin";
          email = "server@example.com";
          initialPassword = "changeme";
          terminal.enable = true;
        };
        storage.devices = [ "/dev/disk/by-id/nvme-server-root-001" ];
        dataPool = {
          name = "ocean";
          mode = "raidz2";
          devices = [
            "/dev/disk/by-id/hdd-server-data-001"
            "/dev/disk/by-id/hdd-server-data-002"
            "/dev/disk/by-id/hdd-server-data-003"
            "/dev/disk/by-id/hdd-server-data-004"
            "/dev/disk/by-id/hdd-server-data-005"
          ];
        };
        modules = [
          {
            networking.hostId = "99aabbcc";
          }
        ];
      }
    );

    inventory-server-no-hardware = evalNixos "inventory-server-no-hardware" (
      (self.lib.mkSystemFlake {
        admin = {
          username = "admin";
          fullName = "Fleet Owner";
          email = "fleet@example.com";
          initialPassword = "changeme";
        };
        defaults.timeZone = "UTC";
        keystoneServices = {
          git.host = "vps";
        };
        hosts = {
          vps = {
            kind = "server";
            hostname = "vps";
            hardware = null;
            configuration = null;
            storage.devices = [ "/dev/disk/by-id/vps-root-001" ];
            modules = [
              {
                networking.hostId = "feedbeef";
              }
            ];
            services.openssh.enable = true;
          };
        };
      }).nixosConfigurations.vps
    );
  };

  homeTests = lib.optionalAttrs (home-manager != null) {
    template-default-macbook = evalHome "template-default-macbook" templateOutputs.homeConfigurations.macbook;

    macos-terminal-only = evalHome "macos-terminal-only" (
      self.lib.mkMacosTerminal {
        system = "aarch64-darwin";
        username = "testuser";
        fullName = "Mac User";
        email = "mac@example.com";
      }
    );
  };

  tests = nixosTests // homeTests;
in
pkgs.runCommand "test-template-evaluation"
  {
    buildInputs = builtins.attrValues tests;
  }
  ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: drv: ''
        cp ${drv}/${name}.json $out/${name}.json
      '') tests
    )}
  ''
