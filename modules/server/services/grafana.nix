# Keystone Grafana Service Module
#
# Grafana is an observability platform for metrics visualization.
# Default subdomain: grafana
# Default port: 3002
# Default access: tailscale
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.grafana;
in
{
  options.keystone.server.services.grafana = serverLib.mkServiceOptions {
    description = "Grafana observability platform";
    subdomain = "grafana";
    port = 3002;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.grafana = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };
  };
}
