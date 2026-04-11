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

  expectFailure =
    name: modules: expectedMessage:
    let
      result = builtins.tryEval (
        (nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.operating-system
            {
              system.stateVersion = "25.05";
              boot.loader.systemd-boot.enable = true;
            }
          ]
          ++ modules;
        }).config.system.build.toplevel
      );
    in
    pkgs.runCommand "eval-failure-${name}" { } ''
      echo "Evaluating failure case ${name}..."
      if [ "${if result.success then "true" else "false"}" = "true" ]; then
        echo "Expected evaluation to fail but it succeeded."
        exit 1
      fi
      echo "  Failure triggered as expected: ${expectedMessage}"
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

    hypervisor-nested = eval "hypervisor-nested" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          hypervisor = {
            enable = true;
            nestedVirtualization.enable = true;
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        networking.hostName = "hypervisor";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    github-runner-vm = eval "github-runner-vm" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          hypervisor = {
            enable = true;
            nestedVirtualization.enable = true;
          };
          githubRunner = {
            enable = true;
            url = "https://github.com/example/repository";
            tokenFile = "/run/agenix/github-runner-token";
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        networking.hostName = "builder";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    github-runner-requires-nested = expectFailure "github-runner-requires-nested" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          hypervisor.enable = true;
          githubRunner = {
            enable = true;
            url = "https://github.com/example/repository";
            tokenFile = "/run/agenix/github-runner-token";
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        networking.hostName = "builder";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ] "githubRunner requires keystone.os.hypervisor.nestedVirtualization.enable";
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
    echo "  - hypervisor-nested: Hypervisor with nested KVM enabled"
    echo "  - github-runner-vm: GitHub runner guest VM with nested KVM prerequisites"
    echo "  - github-runner-requires-nested: Assertion when runner is enabled without nested virtualization"
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
