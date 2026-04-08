# OS module evaluation test
#
# This test verifies that the OS module evaluates correctly with various
# configuration options. It doesn't boot a VM (which would require disko
# to actually partition disks), but validates the module's NixOS options
# and configuration generation.
#
# Build: nix build .#test-os-evaluation
#
{
  pkgs,
  lib,
  self,
}:
# This is a simple evaluation test, not a VM test
# We verify the module evaluates without errors for various configurations
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";

  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
      socketsJson = builtins.toJSON (builtins.attrNames result.config.systemd.sockets);
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Services: ${servicesJson}"
      echo "  Sockets: ${socketsJson}"
      touch $out
    '';

  tests = {
    minimal-zfs = eval "minimal-zfs" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    full-zfs = eval "full-zfs" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [
              "/dev/vda"
              "/dev/vdb"
            ];
            mode = "mirror";
            swap.size = "16G";
            zfs = {
              compression = "zstd";
              arcMax = "8G";
              autoScrub = true;
            };
          };
          secureBoot.enable = true;
          tpm = {
            enable = true;
            pcrs = [
              1
              7
            ];
          };
          remoteUnlock = {
            enable = true;
            authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 test@localhost" ];
            port = 2222;
          };
          ssh.enable = true;
          users.admin = {
            fullName = "Admin User";
            email = "admin@example.com";
            extraGroups = [ "wheel" ];
            initialPassword = "adminpass";
            terminal.enable = true;
            zfs.quota = "100G";
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    ext4-simple = eval "ext4-simple" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    ext4-hibernate = eval "ext4-hibernate" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
            swap.size = "16G";
            hibernate.enable = true;
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    journal-remote-server = eval "journal-remote-server" [
      {
        keystone = {
          domain = "example.com";
          hosts.ocean = {
            hostname = "journal-server";
            role = "server";
            journalRemote = true;
          };
          os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/vda" ];
            };
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
            };
          };
        };
        networking.hostName = "journal-server";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    journal-remote-client = eval "journal-remote-client" [
      {
        keystone = {
          domain = "example.com";
          hosts.ocean = {
            hostname = "ocean";
            role = "server";
            journalRemote = true;
          };
          os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/vda" ];
            };
            journalRemote.serverHost = "ocean";
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
            };
          };
        };
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    journal-remote-client-no-domain = eval "journal-remote-client-no-domain" [
      {
        keystone = {
          hosts.ocean = {
            hostname = "ocean";
            role = "server";
            journalRemote = true;
          };
          os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/vda" ];
            };
            journalRemote.serverHost = "ocean";
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
            };
          };
        };
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];
    credstore-recovery-config =
      let
        # Evaluate a ZFS config and verify credstore recovery policy
        result = nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.operating-system
            {
              system.stateVersion = "25.05";
              boot.loader.systemd-boot.enable = true;
              keystone.os = {
                enable = true;
                storage = {
                  type = "zfs";
                  devices = [ "/dev/vda" ];
                };
                users.testuser = {
                  fullName = "Test User";
                  initialPassword = "testpass";
                };
              };
              networking.hostId = "deadbeef";
              fileSystems."/" = {
                device = lib.mkForce "rpool/crypt/system";
                fsType = lib.mkForce "zfs";
              };
            }
          ];
        };

        credstoreOpts = result.config.boot.initrd.luks.devices.credstore.crypttabExtraOpts;
        hasTokenTimeout = lib.any (opt: lib.hasPrefix "token-timeout=" opt) credstoreOpts;
        rpoolLoadKey = result.config.boot.initrd.systemd.services.rpool-load-key;
        rpoolScript = rpoolLoadKey.script or "";
        hasRpoolDiagnostics = builtins.match ".*CRITICAL.*credstore.*" rpoolScript != null;
      in
      pkgs.runCommand "eval-credstore-recovery-config" { } ''
        echo "Evaluating credstore-recovery-config..."

        # Verify token-timeout is set in credstore crypttab options
        ${
          if hasTokenTimeout then
            ''
              echo "  PASS: credstore crypttabExtraOpts includes token-timeout"
            ''
          else
            ''
              echo "  FAIL: credstore crypttabExtraOpts missing token-timeout" >&2
              echo "  Got: ${builtins.toJSON credstoreOpts}" >&2
              exit 1
            ''
        }

        # Verify rpool-load-key has diagnostic error messages
        ${
          if hasRpoolDiagnostics then
            ''
              echo "  PASS: rpool-load-key includes credstore failure diagnostics"
            ''
          else
            ''
              echo "  FAIL: rpool-load-key missing credstore failure diagnostics" >&2
              exit 1
            ''
        }

        echo "  All credstore recovery policy assertions passed."
        touch $out
      '';
  };
in
pkgs.runCommand "test-os-evaluation"
  {
    nativeBuildInputs = lib.attrValues tests;
  }
  ''
    echo "OS module evaluation tests"
    echo "========================="
    echo ""
    echo "This test verifies that the OS module options are correctly defined"
    echo "and can be evaluated with various configurations."
    echo ""
    echo "Configurations tested:"
    echo "  - minimal-zfs: Minimal ZFS setup"
    echo "  - full-zfs: Full ZFS with all options"
    echo "  - ext4-simple: Simple ext4 setup"
    echo "  - ext4-hibernate: ext4 with hibernation enabled"
    echo "  - journal-remote-server: Journal collection server (HTTPS via nginx)"
    echo "  - journal-remote-client: Journal upload client (HTTPS via nginx)"
    echo "  - journal-remote-client-no-domain: Journal upload client (HTTP fallback)"
    echo "  - credstore-recovery-config: Credstore TPM fallback recovery policy"
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
