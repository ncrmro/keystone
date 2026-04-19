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

  # Evaluate a config and emit service/socket names. When `check` is
  # supplied it is called with the evaluated `config` and must return a
  # shell snippet (runs inside `runCommand`) that fails the build when an
  # invariant is violated. This turns eval tests into behavioral
  # assertions rather than shape-only checks.
  eval = name: modules: evalWith name modules (_: "");

  evalWith =
    name: modules: check:
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
      checkScript = check result.config;
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Services: ${servicesJson}"
      echo "  Sockets: ${socketsJson}"
      ${checkScript}
      touch $out
    '';

  # Emit a value via toPretty for grepping in checks.
  prettyFile = name: v: pkgs.writeText name (lib.generators.toPretty { } v);

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

    # ZFS backup with same-host (local) target — ocean backs up rpool → ocean pool on itself.
    # Behavioral: the local target must emit a plain-dataset syncoid command
    # (no `user@host:` prefix, no `--sshkey`). A regression to `ocean:ocean`
    # being treated as SSH to host `ocean` would fail this check.
    zfs-backup-local =
      evalWith "zfs-backup-local"
        [
          {
            keystone.hosts = {
              ocean = {
                hostname = "ocean";
                role = "server";
                hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
                zfs = {
                  backups.rpool.targets = [
                    "ocean:ocean"
                    "maia:lake"
                  ];
                };
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
            networking.hostName = "ocean";
            networking.hostId = "deadbeef";
            fileSystems."/" = {
              device = lib.mkForce "rpool/crypt/system";
              fsType = lib.mkForce "zfs";
            };
          }
        ]
        (
          config:
          let
            cmds = config.services.syncoid.commands or { };
            localName = "rpool-local-ocean";
            remoteName = "rpool-to-maia";
            localCmd = cmds.${localName} or null;
            remoteCmd = cmds.${remoteName} or null;
          in
          ''
            echo "== zfs-backup-local behavioral checks =="

            # Assert the local command is declared.
            if [ "${if localCmd == null then "missing" else "ok"}" != "ok" ]; then
              echo "FAIL: expected syncoid command '${localName}' for local target 'ocean:ocean'"
              exit 1
            fi

            # Assert the local command's target is a plain dataset path — no '@'
            # (user@host) and no ':' (host:dataset). A regression to treating
            # 'ocean:ocean' as an SSH target would produce 'ocean-sync@ocean:ocean/...'.
            localTarget=${lib.escapeShellArg (if localCmd == null then "" else localCmd.target)}
            echo "  local target: $localTarget"
            case "$localTarget" in
              *@*) echo "FAIL: local target contains '@' (SSH user prefix): $localTarget"; exit 1;;
              *:*) echo "FAIL: local target contains ':' (SSH host:dataset): $localTarget"; exit 1;;
            esac

            # Assert the local command does NOT carry --sshkey in extraArgs.
            localExtraArgs=${
              prettyFile "local-extra" (if localCmd == null then [ ] else localCmd.extraArgs or [ ])
            }
            if ${pkgs.gnugrep}/bin/grep -q -- '--sshkey' "$localExtraArgs"; then
              echo "FAIL: local syncoid command carries --sshkey"
              cat "$localExtraArgs"
              exit 1
            fi

            # Assert NO command of the SSH-style shape exists for this local target
            # (i.e. no "rpool-to-ocean" command with an SSH target).
            ${
              if cmds ? "rpool-to-ocean" then
                ''
                  echo "FAIL: unexpected SSH-style command 'rpool-to-ocean' was emitted for a local target"
                  exit 1
                ''
              else
                ''
                  echo "  confirmed no rpool-to-ocean SSH-style command"
                ''
            }

            # Sanity: the remote target (maia:lake) still uses SSH-style form.
            remoteTarget=${lib.escapeShellArg (if remoteCmd == null then "" else remoteCmd.target)}
            echo "  remote target: $remoteTarget"
            case "$remoteTarget" in
              *@*:*) : ;;
              *) echo "FAIL: remote target is not in user@host:dataset form: $remoteTarget"; exit 1;;
            esac
          ''
        );

    # ZFS backup with poolImportServices wired — ocean imports its 'ocean' pool via a custom service.
    # Behavioral: the resulting syncoid and receiver-init units must carry
    # `after`/`requires` on `import-ocean.service`.
    zfs-backup-pool-import =
      evalWith "zfs-backup-pool-import"
        [
          {
            keystone.hosts = {
              ocean = {
                hostname = "ocean";
                role = "server";
                hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
                zfs = {
                  backups.rpool.targets = [
                    "ocean:ocean"
                    "maia:lake"
                  ];
                };
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
                zfs.backup.poolImportServices = {
                  ocean = "import-ocean";
                };
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
        ]
        (
          config:
          let
            syncoidUnit = config.systemd.services."syncoid-rpool-local-ocean" or null;
            receiverUnit = config.systemd.services."zfs-backup-receiver-init" or null;
            afterFile = prettyFile "syncoid-after" (
              if syncoidUnit == null then [ ] else syncoidUnit.after or [ ]
            );
            requiresFile = prettyFile "syncoid-requires" (
              if syncoidUnit == null then [ ] else syncoidUnit.requires or [ ]
            );
          in
          ''
            echo "== zfs-backup-pool-import behavioral checks =="

            if [ "${if syncoidUnit == null then "missing" else "ok"}" != "ok" ]; then
              echo "FAIL: expected syncoid-rpool-local-ocean unit to exist"
              exit 1
            fi

            # Sender side: syncoid unit for the local target must depend on import-ocean.service.
            if ! ${pkgs.gnugrep}/bin/grep -q 'import-ocean.service' ${afterFile}; then
              echo "FAIL: syncoid-rpool-local-ocean.after is missing import-ocean.service"
              cat ${afterFile}
              exit 1
            fi
            if ! ${pkgs.gnugrep}/bin/grep -q 'import-ocean.service' ${requiresFile}; then
              echo "FAIL: syncoid-rpool-local-ocean.requires is missing import-ocean.service"
              cat ${requiresFile}
              exit 1
            fi
            echo "  sender syncoid unit depends on import-ocean.service"

            # Receiver side: the dataset-init oneshot must also depend on import-ocean.service.
            # This host (ocean) receives its own local backup into pool 'ocean'.
            ${
              if receiverUnit == null then
                ''
                  echo "  (no zfs-backup-receiver-init — host has no incoming backups)"
                ''
              else
                ''
                  receiverAfter=${prettyFile "recv-after" (receiverUnit.after or [ ])}
                  receiverRequires=${prettyFile "recv-requires" (receiverUnit.requires or [ ])}
                  if ! ${pkgs.gnugrep}/bin/grep -q 'import-ocean.service' "$receiverAfter"; then
                    echo "FAIL: zfs-backup-receiver-init.after is missing import-ocean.service"
                    cat "$receiverAfter"
                    exit 1
                  fi
                  if ! ${pkgs.gnugrep}/bin/grep -q 'import-ocean.service' "$receiverRequires"; then
                    echo "FAIL: zfs-backup-receiver-init.requires is missing import-ocean.service"
                    cat "$receiverRequires"
                    exit 1
                  fi
                  echo "  receiver init unit depends on import-ocean.service"
                ''
            }
          ''
        );

    # ZFS backup receiver — host targeted by another host's backups.
    # Behavioral: with poolImportServices set for the incoming target pool,
    # the zfs-backup-receiver-init unit must carry after/requires on
    # import-ocean.service.
    zfs-backup-receiver =
      evalWith "zfs-backup-receiver"
        [
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
                zfs.backup.poolImportServices = {
                  ocean = "import-ocean";
                };
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
        ]
        (
          config:
          let
            receiverUnit = config.systemd.services."zfs-backup-receiver-init" or null;
            afterFile = prettyFile "recv-after" (
              if receiverUnit == null then [ ] else receiverUnit.after or [ ]
            );
            requiresFile = prettyFile "recv-requires" (
              if receiverUnit == null then [ ] else receiverUnit.requires or [ ]
            );
          in
          ''
            echo "== zfs-backup-receiver behavioral checks =="
            if [ "${if receiverUnit == null then "missing" else "ok"}" != "ok" ]; then
              echo "FAIL: expected zfs-backup-receiver-init unit to exist"
              exit 1
            fi
            if ! ${pkgs.gnugrep}/bin/grep -q 'import-ocean.service' ${afterFile}; then
              echo "FAIL: zfs-backup-receiver-init.after is missing import-ocean.service"
              cat ${afterFile}
              exit 1
            fi
            if ! ${pkgs.gnugrep}/bin/grep -q 'import-ocean.service' ${requiresFile}; then
              echo "FAIL: zfs-backup-receiver-init.requires is missing import-ocean.service"
              cat ${requiresFile}
              exit 1
            fi
            echo "  receiver init unit depends on import-ocean.service"
          ''
        );
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
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
