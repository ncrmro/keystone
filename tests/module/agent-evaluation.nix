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
}:
let
  nixosSystem =
    if nixpkgs != null
    then nixpkgs.lib.nixosSystem
    else import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Helper: evaluate a NixOS config and serialize a config value to prove evaluation.
  # Uses builtins.toJSON on users.users to force module evaluation of agent user
  # creation without pulling in the full system build (which needs lanzaboote/cargo).
  eval = name: modules: let
    result = nixosSystem {
      system = "x86_64-linux";
      modules =
        [
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
  in
    pkgs.runCommand "eval-${name}" {} ''
      echo "Evaluating ${name}..."
      echo "  Users: ${usersJson}"
      echo "  Groups: ${groupsJson}"
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
            devices = ["/dev/vda"];
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
            devices = ["/dev/vda"];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
          agents.researcher = {
            fullName = "Research Agent";
            email = "researcher@ks.systems";
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
            devices = ["/dev/vda"];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
          agents = {
            researcher = {
              fullName = "Research Agent";
              email = "researcher@ks.systems";
            };
            coder = {
              fullName = "Coding Agent";
              email = "coder@ks.systems";
              terminal.enable = true;
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
            devices = ["/dev/vda"];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
          };
          agents.researcher = {
            uid = 4050;
            fullName = "Research Agent";
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
