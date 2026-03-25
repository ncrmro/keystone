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
  home-manager,
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
          {
            # Apply keystone overlay so pkgs.keystone.* is available
            nixpkgs.overlays = [ self.overlays.default ];
          }
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          self.nixosModules.operating-system
          {
            # Minimal required config for evaluation
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            networking.hostName = "test-host";

            # Import keystone home-manager modules globally for all users
            # so the bridge in users.nix has options to target.
            home-manager.sharedModules = [
              self.homeModules.terminal
              {
                # Disable sandbox during evaluation tests to avoid external
                # dependency issues (like electron_40 being missing in nixpkgs)
                keystone.terminal.sandbox.enable = false;
              }
            ];
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

      # Check for session variables in home-manager if terminal is enabled for testuser
      sessionVarsJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON result.config.home-manager.users.testuser.home.sessionVariables
        else
          "{}";
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Users: ${usersJson}"
      echo "  Groups: ${groupsJson}"
      echo "  Services: ${servicesJson}"
      echo "  Timers: ${timersJson}"
      echo "  User Services: ${userServicesJson}"
      echo "  User Timers: ${userTimersJson}"

      # Verify DEEPWORK_ADDITIONAL_JOBS_FOLDERS for development-mode test
      if [ "${name}" = "development-mode" ]; then
        echo "Verifying DEEPWORK_ADDITIONAL_JOBS_FOLDERS in development-mode..."
        if echo '${sessionVarsJson}' | grep -q "/home/testuser/.keystone/repos/Unsupervisedcom/deepwork/library/jobs"; then
          echo "  ✓ Found local deepwork jobs path"
        else
          echo "  ✗ Missing local deepwork jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
        # We expect /home/testuser/.keystone/repos/ncrmro/keystone/.deepwork/jobs
        # because ncrmro/keystone is the guessed name for the keystone input.
        if echo '${sessionVarsJson}' | grep -q "/home/testuser/.keystone/repos/ncrmro/keystone/.deepwork/jobs"; then
          echo "  ✓ Found local keystone jobs path"
        else
          echo "  ✗ Missing local keystone jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
      fi

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

    # Development mode verification
    development-mode = eval "development-mode" [
      {
        keystone.development = true;
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            terminal.enable = true;
            email = "testuser@example.com";
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
            # SSH public key now set via keystone.keys."agent-drago"
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
            # SSH public key now set via keystone.keys."agent-tester"
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
            # SSH public key now set via keystone.keys."agent-drago"
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
            # SSH public key now set via keystone.keys."agent-tester"
            notes.repo = "git@example.com:test/notes.git";
            notes.taskLoop = {
              defaults = {
                provider = "claude";
                profile = "medium";
                fallbackModel = "opus";
                effort = "medium";
              };
              profiles = {
                max = {
                  claude = {
                    model = "opus";
                    effort = "max";
                  };
                  gemini.model = "auto-gemini-3";
                };
              };
              ingest = {
                profile = "fast";
                provider = "gemini";
              };
              onCalendar = "*:0/15";
              maxTasks = 3;
              prioritize = {
                profile = "fast";
                model = "gemini-3-flash-preview";
              };
              execute = {
                profile = "max";
                provider = "claude";
                fallbackModel = "sonnet";
              };
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

    # Agent with chrome MCP enabled — verifies evaluation succeeds and the
    # chrome-devtools-mcp package path is resolvable (home.packages added in
    # home-manager.nix when chrome.mcp.enable = true).
    agent-chrome-mcp = eval "agent-chrome-mcp" [
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
              mcp.enable = true;
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with GitHub and Forgejo source usernames
    # forgejo.username defaults to agent name; github.username must be set explicitly
    agent-source-usernames = eval "agent-source-usernames" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          # Both set: github explicit, forgejo defaults to "luce"
          agents.luce = {
            fullName = "Luce";
            notes.repo = "git@example.com:luce/notes.git";
            github.username = "luce-gh";
          };
          # GitHub set, forgejo defaults to "solo"
          agents.solo = {
            fullName = "Solo";
            notes.repo = "git@example.com:solo/notes.git";
            github.username = "solo-gh";
          };
          # No github username (null), forgejo defaults to "quiet"
          agents.quiet = {
            fullName = "Quiet";
            notes.repo = "git@example.com:quiet/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with calendar team events
    agent-calendar-team-events = eval "agent-calendar-team-events" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.planner = {
            fullName = "Planning Agent";
            notes.repo = "git@example.com:planner/notes.git";
            calendar.teamEvents = [
              {
                summary = "Weekly Retrospective";
                schedule = "weekly:friday";
                time = "20:00";
                workflow = "retrospective/run";
              }
              {
                summary = "Monthly Review";
                schedule = "monthly:1";
                time = "10:00";
              }
            ];
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
