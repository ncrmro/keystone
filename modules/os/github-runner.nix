{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.githubRunner;

  runnerInstanceName = "primary";
  runnerUser = "github-runner";
  runnerServiceName = "github-runner-${runnerInstanceName}";
  guestSystemName = "${cfg.name}-vm";

  evalConfig = import "${pkgs.path}/nixos/lib/eval-config.nix";

  guestSystem = evalConfig {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      "${pkgs.path}/nixos/modules/virtualisation/qemu-vm.nix"
      (
        { modulesPath, ... }:
        {
          imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

          system.name = guestSystemName;
          system.stateVersion = cfg.stateVersion;

          networking.hostName = cfg.vm.hostName;
          networking.useDHCP = mkDefault true;
          networking.firewall.enable = true;

          boot.kernelModules = [ "kvm" ];

          nix.settings = {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
            trusted-users = [
              "root"
              runnerUser
            ];
          };

          users.groups.kvm = { };
          users.groups.${runnerUser} = { };
          users.users.${runnerUser} = {
            isSystemUser = true;
            group = runnerUser;
            extraGroups = [ "kvm" ];
            createHome = true;
            home = "/var/lib/${runnerUser}";
          };

          systemd.services.github-runner-token = {
            description = "Materialize GitHub runner token for the guest runner service";
            before = [ "${runnerServiceName}.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ImportCredential = [ "github-runner-token" ];
              RuntimeDirectory = "github-runner";
              RuntimeDirectoryMode = "0700";
            };
            script = ''
              install -Dm600 "$CREDENTIALS_DIRECTORY/github-runner-token" /run/github-runner/token
            '';
          };

          services.github-runners.${runnerInstanceName} = {
            enable = true;
            url = cfg.url;
            tokenFile = "/run/github-runner/token";
            tokenType = cfg.tokenType;
            name = cfg.name;
            runnerGroup = cfg.runnerGroup;
            extraLabels = cfg.extraLabels;
            noDefaultLabels = cfg.noDefaultLabels;
            replace = cfg.replace;
            ephemeral = cfg.ephemeral;
            user = runnerUser;
            group = runnerUser;
            extraPackages = with pkgs; [
              curl
              git
              jq
              qemu_kvm
            ];
            serviceOverrides = {
              NoNewPrivileges = false;
              PrivateDevices = false;
              PrivateMounts = false;
              PrivateTmp = false;
              PrivateUsers = false;
              ProtectControlGroups = false;
              ProtectHome = false;
              ProtectKernelModules = false;
              ProtectKernelTunables = false;
              ProtectSystem = false;
              RestrictNamespaces = false;
              RestrictSUIDSGID = false;
              SystemCallFilter = [ "" ];
            };
          };

          systemd.services.${runnerServiceName} = {
            after = [ "github-runner-token.service" ];
            requires = [ "github-runner-token.service" ];
          };

          virtualisation = {
            graphics = false;
            memorySize = cfg.vm.memorySize;
            cores = cfg.vm.cores;
            diskSize = cfg.vm.diskSize;
            diskImage = "${cfg.vm.stateDir}/disk.qcow2";
            mountHostNixStore = false;
            useNixStoreImage = true;
            qemu.options = [
              "-enable-kvm"
              "-cpu"
              "host"
            ]
            ++ cfg.vm.extraQemuOptions;
            credentials.github-runner-token.source = cfg.tokenFile;
          };
        }
      )
    ];
  };
in
{
  options.keystone.os.githubRunner = {
    enable = mkEnableOption "an isolated GitHub Actions runner guest VM with nested KVM support";

    url = mkOption {
      type = types.str;
      example = "https://github.com/ncrmro/keystone";
      description = "Repository or organization URL used to register the GitHub runner.";
    };

    tokenFile = mkOption {
      type = types.path;
      example = "/run/agenix/github-runner-token";
      description = ''
        Host path to a GitHub runner registration credential. This is passed
        into the guest with systemd credentials rather than by broad host-path
        sharing.
      '';
    };

    tokenType = mkOption {
      type = types.enum [
        "auto"
        "access"
        "registration"
      ];
      default = "auto";
      description = "Token type passed through to services.github-runners inside the guest.";
    };

    name = mkOption {
      type = types.str;
      default = "${config.networking.hostName}-github-runner";
      description = "Runner name shown in the GitHub Actions UI.";
    };

    stateVersion = mkOption {
      type = types.str;
      default = config.system.stateVersion;
      example = "25.05";
      description = "NixOS state version for the dedicated guest VM.";
    };

    runnerGroup = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional GitHub runner group for the guest runner.";
    };

    extraLabels = mkOption {
      type = types.listOf types.str;
      default = [
        "keystone"
        "nested-kvm"
      ];
      description = "Extra labels advertised by the GitHub runner inside the guest.";
    };

    noDefaultLabels = mkOption {
      type = types.bool;
      default = false;
      description = "Disable the default GitHub runner labels inside the guest.";
    };

    replace = mkOption {
      type = types.bool;
      default = true;
      description = "Replace an existing GitHub runner with the same name.";
    };

    ephemeral = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the runner should re-register after every completed job.";
    };

    vm = {
      hostName = mkOption {
        type = types.str;
        default = "${config.networking.hostName}-github-runner";
        description = "Hostname used inside the dedicated runner guest.";
      };

      memorySize = mkOption {
        type = types.ints.positive;
        default = 8192;
        description = "Memory assigned to the runner guest in MiB.";
      };

      cores = mkOption {
        type = types.ints.positive;
        default = 4;
        description = "Virtual CPU cores assigned to the runner guest.";
      };

      diskSize = mkOption {
        type = types.ints.positive;
        default = 40 * 1024;
        description = "Runner guest disk size in MiB.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "/var/lib/keystone/github-runner";
        description = "Host directory that stores the runner guest disk image and runtime state.";
      };

      extraQemuOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra QEMU options appended to the runner guest launch command.";
      };
    };
  };

  config = mkIf (osCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = osCfg.hypervisor.enable;
        message = "keystone.os.githubRunner requires keystone.os.hypervisor.enable = true.";
      }
      {
        assertion = osCfg.hypervisor.nestedVirtualization.enable;
        message = "keystone.os.githubRunner requires keystone.os.hypervisor.nestedVirtualization.enable = true.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.vm.stateDir} 0750 root root -"
    ];

    systemd.services.keystone-github-runner-vm = {
      description = "Isolated GitHub Actions runner VM";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";
        WorkingDirectory = cfg.vm.stateDir;
      };
      script = ''
        set -euo pipefail
        exec ${guestSystem.config.system.build.vm}/bin/run-${guestSystem.config.system.name}-vm
      '';
    };
  };
}
