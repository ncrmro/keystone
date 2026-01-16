# Keystone Cluster Worker Module
#
# Worker nodes connect to the primer's Headscale server via Tailscale.
# They participate in the WireGuard mesh network.
#
# Usage:
#   keystone.cluster.worker = {
#     enable = true;
#     headscaleUrl = "http://primer:8080";
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.cluster.worker;
in
{
  imports = [
    ./tailscale.nix
  ];

  options.keystone.cluster.worker = {
    enable = mkEnableOption "Keystone Cluster Worker - Tailscale client for mesh networking";

    headscaleUrl = mkOption {
      type = types.str;
      example = "http://primer:8080";
      description = "URL of the Headscale server on the primer";
    };

    authKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Pre-auth key for automatic registration (optional, can be set at runtime)";
    };

    hostname = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Hostname to register with Headscale (defaults to system hostname)";
    };

    acceptRoutes = mkOption {
      type = types.bool;
      default = true;
      description = "Accept routes advertised by other nodes";
    };
  };

  config = mkIf cfg.enable {
    # Assertions
    assertions = [
      {
        assertion = cfg.headscaleUrl != "";
        message = "keystone.cluster.worker.headscaleUrl must be set";
      }
    ];

    # Enable Tailscale submodule
    keystone.cluster.worker.tailscale.enable = true;

    # Enable IP forwarding for mesh traffic
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # Open firewall for WireGuard
    networking.firewall = {
      allowedUDPPorts = [
        41641 # Tailscale/WireGuard
      ];
      # Trust the tailscale interface
      trustedInterfaces = [ "tailscale0" ];
    };
  };
}
