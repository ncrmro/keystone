# Podman-based sandboxing for AI coding agents.
#
# Exports pre-resolved Nix store paths as session variables so that
# podman-agent can mount them directly into containers, skipping the
# GitHub flake-resolution round-trip on every launch.  The env vars
# are optional — podman-agent falls back to `nix build` when unset.
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

      # Pre-resolved store paths — lets podman-agent skip GitHub
      # flake resolution and use these paths directly.
      PODMAN_AGENT_CLAUDE_CODE_PATH = "${pkgs.keystone.claude-code}";
      PODMAN_AGENT_GEMINI_CLI_PATH = "${pkgs.keystone.gemini-cli}";
      PODMAN_AGENT_CODEX_PATH = "${pkgs.keystone.codex}";
      PODMAN_AGENT_GH_PATH = "${pkgs.gh}";
      PODMAN_AGENT_RIPGREP_PATH = "${pkgs.ripgrep}";
      PODMAN_AGENT_PROCPS_PATH = "${pkgs.procps}";
    } // optionalAttrs (cfg.extraSubstituters != [ ]) {
      PODMAN_AGENT_EXTRA_SUBSTITUTERS = concatStringsSep " " cfg.extraSubstituters;
    } // optionalAttrs (cfg.extraTrustedPublicKeys != [ ]) {
      PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS = concatStringsSep " " cfg.extraTrustedPublicKeys;
    };
  };
}
