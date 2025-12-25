{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.keystone.agent;
  keystoneAgentPackage = pkgs.callPackage ../../../packages/keystone-agent {};
in {
  options.keystone.agent = {
    enable = lib.mkEnableOption "Keystone Agent Sandbox system";

    # Sandbox Configuration
    sandbox = {
      memory = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Default RAM allocation in MB for sandboxes";
      };

      vcpus = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Default virtual CPU count for sandboxes";
      };

      nestedVirtualization = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable nested virtualization (KVM passthrough) when supported";
      };

      network = lib.mkOption {
        type = lib.types.enum ["nat" "none" "bridge"];
        default = "nat";
        description = "Default network mode for sandboxes";
      };

      syncMode = lib.mkOption {
        type = lib.types.enum ["manual" "auto-commit" "auto-idle"];
        default = "manual";
        description = "Default sync mode for code changes";
      };

      persist = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Persist sandbox state between sessions";
      };
    };

    # Backend Configuration
    backend = {
      type = lib.mkOption {
        type = lib.types.enum ["microvm" "kubernetes"];
        default = "microvm";
        description = "Sandbox runtime backend";
      };

      microvm = {
        hypervisor = lib.mkOption {
          type = lib.types.enum ["qemu" "firecracker" "cloud-hypervisor"];
          default = "qemu";
          description = "MicroVM hypervisor to use";
        };

        shareType = lib.mkOption {
          type = lib.types.enum ["virtiofs" "9p"];
          default = "virtiofs";
          description = "File sharing mechanism for /workspace/";
        };
      };

      kubernetes = {
        context = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Kubernetes context to use";
        };

        namespace = lib.mkOption {
          type = lib.types.str;
          default = "keystone-agent";
          description = "Kubernetes namespace for sandboxes";
        };

        storageClass = lib.mkOption {
          type = lib.types.str;
          default = "standard";
          description = "Storage class for persistent volumes";
        };
      };
    };

    # Proxy Configuration
    proxy = {
      enable = lib.mkEnableOption "Development server proxy";

      domain = lib.mkOption {
        type = lib.types.str;
        default = "sandbox.local";
        description = "Base domain for proxied services";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Proxy server port";
      };
    };

    # Guest Configuration
    guest = {
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Additional packages to install in guest";
      };

      agents = {
        claudeCode = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install Claude Code in guest";
          };

          autoAccept = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Configure Claude Code to auto-accept operations";
          };
        };

        geminiCli = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Install Gemini CLI in guest";
          };
        };

        codex = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Install Codex in guest";
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Module imports
    imports = [
      ./backends
      ./sync.nix
      ./proxy.nix
    ];

    # Ensure KVM is available for nested virtualization
    boot.kernelModules = lib.mkIf (cfg.sandbox.nestedVirtualization) [
      "kvm-intel"
      "kvm-amd"
    ];

    # Enable nested virtualization in KVM
    boot.extraModprobeConfig = lib.mkIf (cfg.sandbox.nestedVirtualization) ''
      options kvm_intel nested=1
      options kvm_amd nested=1
    '';

    # Install agent CLI globally
    environment.systemPackages = [
      keystoneAgentPackage
    ];

    # Create agent config directory
    system.activationScripts.keystoneAgent = ''
      mkdir -p /var/lib/keystone/agent
      chmod 755 /var/lib/keystone/agent
    '';
  };
}
