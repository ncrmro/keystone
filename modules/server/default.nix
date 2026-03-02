# Keystone Server Module
#
# This module provides optional server services for Keystone infrastructure:
# - VPN (Headscale/Tailscale)
# - Mail server (placeholder)
# - Monitoring (Prometheus/Grafana using NixOS services)
# - Observability (Loki/Alloy)
# - Binary cache (Harmonia)
#
# Usage:
#   keystone.server = {
#     enable = true;
#     domain = "example.com";
#     vpn.enable = true;
#     monitoring.enable = true;
#     binaryCache.enable = true;
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
    ./binary-cache.nix
  ];

  options.keystone.server = {
    enable = mkEnableOption "Keystone server services (VPN, monitoring, mail, binary cache)";

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "example.com";
      description = ''
        Shared top-level domain for server services.
        Sub-services auto-derive their subdomains from this (e.g. harmonia.<domain>).
        Can be overridden per-service.
      '';
    };

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

    # Binary cache configuration
    binaryCache = {
      enable = mkEnableOption "Nix binary cache with Harmonia";
      # Options are defined in binary-cache.nix
    };
  };

  config = mkIf cfg.enable {
    warnings =
      optional (cfg.domain == null)
        "keystone.server.domain is not set. Sub-services cannot auto-derive their subdomains.";
  };
}
