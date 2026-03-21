# Podman container runtime for keystone hosts.
#
# Enables rootless Podman with fuse-overlayfs (required for ZFS), disables
# Docker, and conditionally installs sandbox tooling (agentctl, podman-agent)
# when the terminal sandbox module is active.
#
# See conventions/process.sandbox-agent.md
# Implements REQ-013 (Container Sub-Agent Management)
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.containers;
  # Check if terminal sandbox is enabled (home-manager module)
  hasSandbox = options ? keystone && config.keystone.terminal.sandbox.enable or false;
in
{
  options.keystone.os.containers = {
    enable = mkOption {
      type = types.bool;
      default = osCfg.enable;
      description = "Enable Podman container runtime by default for all keystone hosts";
    };
  };

  config = mkIf (osCfg.enable && cfg.enable) {
    virtualisation.containers.enable = true;
    # CRITICAL: fuse-overlayfs required for rootless podman on ZFS — kernel
    # overlayfs cannot mount on ZFS for unprivileged users (permission denied).
    virtualisation.containers.storage.settings.storage.options.mount_program =
      "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs";
    virtualisation.docker.enable = lib.mkForce false;
    virtualisation.podman = {
      enable = true;
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    environment.systemPackages =
      with pkgs;
      [
        dive
        docker-compose
      ]
      ++ lib.optionals hasSandbox [
        pkgs.keystone.agentctl
        pkgs.keystone.podman-agent
      ];
  };
}
