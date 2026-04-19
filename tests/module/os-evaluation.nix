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

    # ZFS backup sender — host with backups declared in keystone.hosts
    zfs-backup-sender = eval "zfs-backup-sender" [
      {
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 workstation";
            zfs = {
              backups.rpool.targets = [
                "ocean:ocean"
                "maia:lake"
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            sshTarget = "ocean.ts";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
          maia = {
            hostname = "maia";
            role = "server";
            sshTarget = "maia.ts";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaia maia";
          };
        };
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
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # ZFS backup receiver — host targeted by another host's backups
    zfs-backup-receiver = eval "zfs-backup-receiver" [
      {
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 workstation";
            zfs = {
              backups.rpool.targets = [
                "ocean:ocean"
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
        };
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
        networking.hostName = "ocean";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # ZFS backup sender with local (intra-host) target — gap 1
    # Workstation replicates rpool to a local second pool (backup) and also to remote ocean
    zfs-backup-local-target = eval "zfs-backup-local-target" [
      {
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 workstation";
            zfs = {
              backups.rpool.targets = [
                "workstation:backup" # local intra-host replication
                "ocean:ocean" # remote replication
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            sshTarget = "ocean.ts";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
        };
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
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # ZFS backup with poolImportServices — gap 2
    # Receiver gates zfs-backup-init on a non-boot pool import service
    zfs-backup-pool-import = eval "zfs-backup-pool-import" [
      {
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 workstation";
            zfs = {
              backups.rpool.targets = [
                "ocean:ocean"
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
        };
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          # gap 2: gate backup-init on the ocean pool import service
          zfsBackup.poolImportServices.ocean = "import-ocean";
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        networking.hostName = "ocean";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # ZFS backup receiver with SSH key fallback — gap 4
    # Sender has no hostPublicKey; receiver uses keystone.keys fallback
    zfs-backup-key-fallback = eval "zfs-backup-key-fallback" [
      {
        keystone.keys.ncrmro = {
          hosts.ocean.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFallback ocean@ncrmro";
        };
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            # gap 4: no hostPublicKey — receiver must use sshKeyFallbackUser
            zfs = {
              backups.rpool.targets = [
                "ocean:ocean"
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
        };
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          # gap 4: fall back to ncrmro's allKeys for senders without hostPublicKey
          zfsBackup.sshKeyFallbackUser = "ncrmro";
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
        };
        networking.hostName = "ocean";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];
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
    echo "  - zfs-backup-sender: ZFS backup sender with remote targets"
    echo "  - zfs-backup-receiver: ZFS backup receiver"
    echo "  - zfs-backup-local-target: ZFS backup with local intra-host target (gap 1)"
    echo "  - zfs-backup-pool-import: ZFS backup with poolImportServices (gap 2)"
    echo "  - zfs-backup-key-fallback: ZFS backup receiver with SSH key fallback (gap 4)"
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
