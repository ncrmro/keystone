# Tailscale Client Configuration for Worker Nodes
#
# Configures Tailscale to connect to the primer's Headscale server.
# Workers register with the mesh network using pre-auth keys.
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.cluster.worker.tailscale;
  workerCfg = config.keystone.cluster.worker;
in
{
  options.keystone.cluster.worker.tailscale = {
    enable = mkEnableOption "Tailscale client for Headscale connection";

    package = mkOption {
      type = types.package;
      default = pkgs.tailscale;
      description = "Tailscale package to use";
    };

    extraUpFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra flags to pass to tailscale up";
    };
  };

  config = mkIf cfg.enable {
    # Enable the Tailscale service
    services.tailscale = {
      enable = true;
      package = cfg.package;
      useRoutingFeatures = "both";
    };

    # Install tailscale CLI
    environment.systemPackages = [ cfg.package ];

    # Create a helper script for manual registration
    # (useful for testing when auth key isn't set at build time)
    environment.etc."keystone/join-mesh.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        HEADSCALE_URL="${workerCfg.headscaleUrl}"
        AUTH_KEY="''${1:-}"
        HOSTNAME="${if workerCfg.hostname != null then workerCfg.hostname else "$(hostname)"}"

        if [ -z "$AUTH_KEY" ]; then
          echo "Usage: $0 <auth-key>"
          echo ""
          echo "Get an auth key from the primer:"
          echo "  kubectl exec -n headscale-system deploy/headscale -- \\"
          echo "    headscale preauthkeys create --user default --reusable --expiration 1h"
          exit 1
        fi

        echo "Joining mesh network..."
        echo "  Headscale URL: $HEADSCALE_URL"
        echo "  Hostname: $HOSTNAME"

        ${cfg.package}/bin/tailscale up \
          --login-server="$HEADSCALE_URL" \
          --authkey="$AUTH_KEY" \
          --hostname="$HOSTNAME" \
          ${optionalString workerCfg.acceptRoutes "--accept-routes"} \
          --accept-dns=false \
          ${concatStringsSep " " cfg.extraUpFlags}

        echo "Successfully joined mesh network!"
        ${cfg.package}/bin/tailscale status
      '';
    };

    # If auth key is provided at build time, auto-register on boot
    systemd.services.tailscale-autoregister = mkIf (workerCfg.authKey != null) {
      description = "Automatically register with Headscale";
      wantedBy = [ "multi-user.target" ];
      after = [
        "tailscaled.service"
        "network-online.target"
      ];
      requires = [ "tailscaled.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Wait for tailscaled to be ready
        sleep 2

        # Check if already registered
        if ${cfg.package}/bin/tailscale status &>/dev/null; then
          echo "Already registered with Headscale"
          exit 0
        fi

        echo "Registering with Headscale at ${workerCfg.headscaleUrl}..."
        ${cfg.package}/bin/tailscale up \
          --login-server="${workerCfg.headscaleUrl}" \
          --authkey="${workerCfg.authKey}" \
          ${optionalString (workerCfg.hostname != null) "--hostname=${workerCfg.hostname}"} \
          ${optionalString workerCfg.acceptRoutes "--accept-routes"} \
          --accept-dns=false \
          ${concatStringsSep " " cfg.extraUpFlags}

        echo "Successfully registered!"
      '';
    };
  };
}
