# Keystone Harmonia Service Module
#
# Harmonia is a Nix binary cache server.
# Default subdomain: harmonia
# Default port: 5000
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
  cfg = serverCfg.services.harmonia;
in
{
  options.keystone.server.services.harmonia = serverLib.mkServiceOptions {
    description = "Harmonia Nix binary cache";
    subdomain = "harmonia";
    port = 5000;
    access = "tailscale";
    websockets = false;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.harmonia = {
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
