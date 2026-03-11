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

    # TODO: Add push support so containers can populate the cache after builds
    extraSubstituters = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "https://cache.example.com" ];
      description = "Additional Nix substituters (binary caches) available inside the container.";
    };

    extraTrustedPublicKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "cache.example.com-1:AAAA...=" ];
      description = "Public keys for verifying store path signatures from extra substituters.";
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
    } // optionalAttrs (cfg.extraSubstituters != [ ]) {
      PODMAN_AGENT_EXTRA_SUBSTITUTERS = concatStringsSep " " cfg.extraSubstituters;
    } // optionalAttrs (cfg.extraTrustedPublicKeys != [ ]) {
      PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS = concatStringsSep " " cfg.extraTrustedPublicKeys;
    };
  };
}
