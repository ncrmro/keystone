{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.sandbox;
in
{
  options.keystone.terminal.sandbox = {
    enable = mkEnableOption "Podman-based sandboxing for AI coding agents (podman-agent)";

    memory = mkOption {
      type = types.str;
      default = "4g";
      description = "Container memory limit (e.g., '4g', '8g')";
    };

    cpus = mkOption {
      type = types.str;
      default = "4";
      description = "Container CPU limit";
    };

    volumeName = mkOption {
      type = types.str;
      default = "nix-agent-store";
      description = "Podman named volume for persistent /nix store";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.podman-agent
    ];

    home.sessionVariables = {
      PODMAN_AGENT_MEMORY = cfg.memory;
      PODMAN_AGENT_CPUS = cfg.cpus;
      PODMAN_AGENT_VOLUME = cfg.volumeName;
    };
  };
}
