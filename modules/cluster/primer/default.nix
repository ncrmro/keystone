# Keystone Cluster Primer Module
#
# The primer server is the root of trust for a Keystone cluster.
# It runs k3s with Headscale deployed inside Kubernetes.
#
# Usage:
#   keystone.cluster.primer = {
#     enable = true;
#     headscale = {
#       serverUrl = "http://primer:8080";
#       baseDomain = "cluster.local";
#     };
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.cluster.primer;
in {
  imports = [
    ./k3s.nix
    ./headscale.nix
  ];

  options.keystone.cluster.primer = {
    enable = mkEnableOption "Keystone Cluster Primer - k3s server with Headscale";

    clusterName = mkOption {
      type = types.str;
      default = "keystone";
      description = "Name of the Keystone cluster";
    };

    headscale = {
      serverUrl = mkOption {
        type = types.str;
        example = "http://primer:8080";
        description = "URL where Headscale will be accessible";
      };

      baseDomain = mkOption {
        type = types.str;
        default = "cluster.local";
        description = "Base domain for Headscale MagicDNS";
      };

      namespace = mkOption {
        type = types.str;
        default = "headscale-system";
        description = "Kubernetes namespace for Headscale";
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions
    assertions = [
      {
        assertion = cfg.headscale.serverUrl != "";
        message = "keystone.cluster.primer.headscale.serverUrl must be set";
      }
    ];

    # Enable k3s and headscale submodules
    keystone.cluster.primer.k3s.enable = true;
    keystone.cluster.primer.headscaleDeployment.enable = true;

    # Install cluster management tools
    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      k9s
    ];

    # Enable IP forwarding for mesh traffic
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # Open firewall ports
    networking.firewall = {
      allowedTCPPorts = [
        6443 # Kubernetes API
        8080 # Headscale HTTP
        443 # HTTPS
        3478 # DERP STUN
      ];
      allowedUDPPorts = [
        3478 # DERP STUN
        41641 # Tailscale/WireGuard
      ];
    };
  };
}
