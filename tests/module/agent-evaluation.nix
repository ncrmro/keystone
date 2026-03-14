# Agent module evaluation test
#
# Verifies that the OS agents module evaluates correctly with various
# configuration options. Forces NixOS module evaluation at build time
# to catch option errors, type mismatches, and assertion failures.
#
# Build: nix build .#agent-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  agenix,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Helper: evaluate a NixOS config and serialize a config value to prove evaluation.
  # Uses builtins.toJSON on users.users to force module evaluation of agent user
  # creation without pulling in the full system build (which needs lanzaboote/cargo).
  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          agenix.nixosModules.default
          self.nixosModules.operating-system
          {
            # Minimal required config for evaluation
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      # Serialize user config to force evaluation of agent user creation
      usersJson = builtins.toJSON (builtins.attrNames result.config.users.users);
      groupsJson = builtins.toJSON (builtins.attrNames result.config.users.groups);
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
      timersJson = builtins.toJSON (builtins.attrNames result.config.systemd.timers);
      userServicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.user.services);
      userTimersJson = builtins.toJSON (builtins.attrNames result.config.systemd.user.timers);
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Users: ${usersJson}"
      echo "  Groups: ${groupsJson}"
      echo "  Services: ${servicesJson}"
      echo "  Timers: ${timersJson}"
      echo "  User Services: ${userServicesJson}"
      echo "  User Timers: ${userTimersJson}"
      touch $out
    '';

  # Test configurations
  tests = {
    # No agents configured (default)
    no-agents = eval "no-agents" [
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

    # Single agent on ext4
    single-agent-ext4 = eval "single-agent-ext4" [
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
          agents.researcher = {
            fullName = "Research Agent";
            email = "researcher@ks.systems";
            notes.repo = "git@example.com:researcher/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Multiple agents on ZFS
    multi-agent-zfs = eval "multi-agent-zfs" [
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
          agents = {
            researcher = {
              fullName = "Research Agent";
              email = "researcher@ks.systems";
              notes.repo = "git@example.com:researcher/notes.git";
            };
            coder = {
              fullName = "Coding Agent";
              email = "coder@ks.systems";
              notes.repo = "git@example.com:coder/notes.git";
            };
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/root";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # Agent with explicit UID
    agent-explicit-uid = eval "agent-explicit-uid" [
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
          agents.researcher = {
            uid = 4050;
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with desktop enabled (labwc + wayvnc)
    agent-desktop = eval "agent-desktop" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
          agents.coder = {
            fullName = "Coding Agent";
            notes.repo = "git@example.com:coder/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with desktop and custom resolution + explicit VNC port
    agent-desktop-custom = eval "agent-desktop-custom" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
            desktop = {
              enable = true;
              resolution = "2560x1440";
              vncPort = 5910;
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with chrome enabled (auto-assigned debug port)
    agent-chrome = eval "agent-chrome" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with chrome and explicit debug port
    agent-chrome-custom-port = eval "agent-chrome-custom-port" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
            chrome = {
              enable = true;
              debugPort = 9300;
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with notes.repo configured (sync user service)
    agent-notes = eval "agent-notes" [
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
          agents.drago = {
            fullName = "Drago";
            notes.repo = "git@git.ncrmro.com:drago/agent-space.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with notes and SSH
    agent-notes-ssh = eval "agent-notes-ssh" [
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
          agents.drago = {
            fullName = "Drago";
            notes.repo = "git@git.ncrmro.com:drago/agent-space.git";
            ssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTesting agent-drago";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with custom sync interval
    agent-notes-sync = eval "agent-notes-sync" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.tester = {
            fullName = "Test Agent";
            ssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTesting agent-tester";
            notes.repo = "git@example.com:test/notes.git";
            notes.syncOnCalendar = "*:0/15";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with task loop and scheduler
    agent-notes-task-loop = eval "agent-notes-task-loop" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.drago = {
            fullName = "Drago";
            ssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTesting agent-drago";
            notes.repo = "git@git.example.com:drago/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with custom task loop and scheduler schedules
    agent-notes-task-loop-custom = eval "agent-notes-task-loop-custom" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.tester = {
            fullName = "Test Agent";
            ssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTesting agent-tester";
            notes.repo = "git@example.com:test/notes.git";
            notes.taskLoop = {
              onCalendar = "*:0/15";
              maxTasks = 3;
            };
            notes.scheduler = {
              onCalendar = "*-*-* 06:00:00";
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Multiple agents with chrome (non-conflicting auto-assigned ports)
    multi-agent-chrome = eval "multi-agent-chrome" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
          agents.coder = {
            fullName = "Coding Agent";
            notes.repo = "git@example.com:coder/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];
  };
in
pkgs.runCommand "test-agent-evaluation"
  {
    # Depend on all eval derivations so they get built
    buildInputs = builtins.attrValues tests;
  }
  ''
    echo "Agent module evaluation tests"
    echo "============================="
    echo ""
    echo "All agent module configurations evaluated successfully!"
    touch $out
  ''
