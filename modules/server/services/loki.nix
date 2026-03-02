# Keystone Loki Service Module
#
# Loki is a log aggregation system.
# Default subdomain: loki
# Default port: 3100
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
  cfg = serverCfg.services.loki;
in
{
  options.keystone.server.services.loki = serverLib.mkServiceOptions {
    description = "Loki log aggregation";
    subdomain = "loki";
    port = 3100;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.loki = {
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
