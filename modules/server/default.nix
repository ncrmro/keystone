# Keystone Server Module
#
# This module provides optional server services for Keystone infrastructure:
# - VPN (Headscale/Tailscale)
# - Mail server (placeholder)
# - Monitoring (Prometheus/Grafana using NixOS services)
# - Observability (Loki/Alloy)
#
# Usage:
#   keystone.server = {
#     enable = true;
#     vpn.enable = true;
#     monitoring.enable = true;
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.server;
in {
  imports = [
    ./vpn.nix
    ./mail.nix
    ./monitoring.nix
    ./headscale.nix
  ];

  options.keystone.server = {
    enable = mkEnableOption "Keystone server services (VPN, monitoring, mail)";

    # VPN configuration
    vpn = {
      enable = mkEnableOption "VPN server with Headscale (Kubernetes-based)";
      # Options are defined in vpn.nix
    };

    # Mail server configuration
    mail = {
      enable = mkEnableOption "Mail server (placeholder for future implementation)";
      # Options are defined in mail.nix
    };

    # Monitoring configuration (NixOS services)
    monitoring = {
      enable = mkEnableOption "Monitoring stack with Prometheus and Grafana (NixOS services)";
      # Options are defined in monitoring.nix
    };

    # Headscale exit node configuration
    headscale = {
      enable = mkEnableOption "Headscale exit node (placeholder for future implementation)";
      # Options are defined in headscale.nix
    };
  };

  config = mkIf cfg.enable {
    # No base configuration needed - services are opt-in
  };
}
