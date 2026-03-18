# Keystone Host Registry
#
# Shared option declaring identity and connection metadata for all hosts in
# the infrastructure. Follows the same pattern as domain.nix and mail.nix —
# set once per infrastructure, consumed by multiple modules and deploy scripts.
#
# Usage:
#   keystone.hosts = {
#     ocean = {
#       hostname = "ocean";
#       sshTarget = "ocean.mercury";
#       fallbackIP = "192.168.1.10";
#       buildOnRemote = true;
#     };
#   };
#
# The `ks` CLI reads this data at runtime via: nix eval -f hosts.nix --json <host>
{ lib, ... }:
with lib; {
  options.keystone.hosts = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        hostname = mkOption {
          type = types.str;
          description = "The networking.hostName of this host (may differ from flake config name).";
        };
        sshTarget = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "SSH target for remote deploys (Tailscale hostname or IP). null = local-only host.";
        };
        fallbackIP = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "LAN IP fallback when sshTarget is unreachable via Tailscale.";
        };
        buildOnRemote = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to pass --build-host for remote deploys (build on remote machine).";
        };
        role = mkOption {
          type = types.enum [ "client" "server" "agent" ];
          description = "Tailscale network role for this host (mandatory).";
        };
        hostPublicKey = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "SSH host public key (/etc/ssh/ssh_host_ed25519_key.pub).";
        };
        zfs = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              backups = mkOption {
                type = types.attrsOf (types.submodule {
                  options = {
                    targets = mkOption {
                      type = types.listOf types.str;
                      description = "Backup targets as 'host:pool' strings (e.g. 'maia:lake')";
                    };
                  };
                });
                default = {};
                description = "Per-pool backup target declarations. Key is source pool name.";
              };
            };
          });
          default = null;
          description = "ZFS backup topology for this host.";
        };
      };
    });
    default = {};
    description = ''
      Host identity and connection metadata for all NixOS hosts. Keys MUST match
      nixosConfigurations names in flake.nix. Consumed by the `ks` CLI (ks build, ks update).
    '';
  };
}
