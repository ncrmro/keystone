# Template config evaluation test
#
# Validates that generated TUI configurations evaluate correctly via
# nixosSystem. Uses a mkTemplateConfig helper that mirrors what the TUI
# will produce (REQ-003.2), ensuring the output contract is buildable.
#
# Each test config is serialized to JSON for inspection:
#   nix build .#template-evaluation && cat result/minimal-zfs.json
#
# Build: nix build .#template-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
}:
let
  nixosSystem =
    if nixpkgs != null then nixpkgs.lib.nixosSystem else import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Helper: build a NixOS config the same way the TUI will generate it.
  # Accepts the REQ-002 data model and produces a NixOS module list.
  # This is the contract that the TUI's code generation must match.
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
    let
      baseModules = [
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
            } // lib.optionalAttrs (storageType == "ext4" && hibernateEnable) { hibernate.enable = true; };
            secureBoot.enable = secureBootEnable;
            tpm.enable = tpmEnable;
            ssh.enable = sshEnable;
            remoteUnlock = lib.mkIf remoteUnlockEnable {
              enable = true;
              authorizedKeys = remoteUnlockAuthorizedKeys;
            };
            inherit users;
          };

          # Required filesystem stubs for evaluation
          fileSystems."/" = {
            device =
              if storageType == "zfs" then lib.mkForce "rpool/root" else lib.mkForce "/dev/vda2";
            fsType = lib.mkForce (if storageType == "zfs" then "zfs" else "ext4");
          };

          nix.settings.trusted-users = [
            "root"
            "@wheel"
          ];
        }
      ] ++ lib.optionals desktopEnable [ self.nixosModules.desktop ] ++ extraModules;
    in
    baseModules;

  # Evaluate a config and serialize key attributes to JSON for inspection
  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        inherit modules;
      };
      usersJson = builtins.toJSON (builtins.attrNames result.config.users.users);
      groupsJson = builtins.toJSON (builtins.attrNames result.config.users.groups);
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
    in
    pkgs.runCommand "eval-template-${name}" { } ''
      mkdir -p $out
      cat > $out/${name}.json <<'ENDJSON'
      {
        "name": "${name}",
        "users": ${usersJson},
        "groups": ${groupsJson},
        "services": ${servicesJson}
      }
      ENDJSON
      echo "  ${name}: OK ($(echo '${usersJson}' | ${pkgs.jq}/bin/jq length) users, $(echo '${servicesJson}' | ${pkgs.jq}/bin/jq length) services)"
    '';

  # Test configurations matching REQ-003.4
  tests = {
    # Single-disk ZFS, one user, basic defaults
    minimal-zfs = eval "minimal-zfs" (mkTemplateConfig {
      hostname = "minimal-zfs-host";
      hostId = "aabbccdd";
      storageType = "zfs";
      storageDevices = [ "/dev/disk/by-id/nvme-test-disk-001" ];
      users.admin = {
        fullName = "Admin User";
        initialPassword = "changeme";
        extraGroups = [ "wheel" ];
        terminal.enable = true;
      };
    });

    # Two-disk ZFS mirror, full security, user with SSH keys
    mirror-zfs = eval "mirror-zfs" (mkTemplateConfig {
      hostname = "mirror-zfs-host";
      hostId = "11223344";
      storageType = "zfs";
      storageDevices = [
        "/dev/disk/by-id/nvme-test-disk-001"
        "/dev/disk/by-id/nvme-test-disk-002"
      ];
      storageMode = "mirror";
      secureBootEnable = true;
      tpmEnable = true;
      remoteUnlockEnable = true;
      remoteUnlockAuthorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeTestKey001 admin@workstation" ];
      users.admin = {
        fullName = "Admin User";
        email = "admin@example.com";
        extraGroups = [ "wheel" ];
        initialPassword = "changeme";
        authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeTestKey001 admin@workstation" ];
        terminal.enable = true;
      };
    });

    # Single-disk ext4, one user
    ext4-simple = eval "ext4-simple" (mkTemplateConfig {
      hostname = "ext4-simple-host";
      hostId = "55667788";
      storageType = "ext4";
      storageDevices = [ "/dev/disk/by-id/nvme-test-disk-001" ];
      users.admin = {
        fullName = "Admin User";
        initialPassword = "changeme";
        extraGroups = [ "wheel" ];
      };
    });

    # ZFS with desktop module enabled, user with desktop + terminal
    zfs-desktop = eval "zfs-desktop" (mkTemplateConfig {
      hostname = "zfs-desktop-host";
      hostId = "99aabbcc";
      storageType = "zfs";
      storageDevices = [ "/dev/disk/by-id/nvme-test-disk-001" ];
      desktopEnable = true;
      users.admin = {
        fullName = "Desktop User";
        email = "desktop@example.com";
        extraGroups = [
          "wheel"
          "networkmanager"
          "video"
          "audio"
        ];
        initialPassword = "changeme";
        terminal.enable = true;
        desktop = {
          enable = true;
          hyprland.modifierKey = "SUPER";
        };
      };
    });
  };
in
pkgs.runCommand "test-template-evaluation"
  {
    buildInputs = builtins.attrValues tests;
  }
  ''
    mkdir -p $out
    echo "Template config evaluation tests"
    echo "================================="
    echo ""
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: drv: ''
        cp ${drv}/${name}.json $out/${name}.json
      '') tests
    )}
    echo "All template configurations evaluated successfully!"
    echo ""
    echo "Inspect output: cat result/<config-name>.json"
    echo "Configs: ${lib.concatStringsSep ", " (builtins.attrNames tests)}"
  ''
