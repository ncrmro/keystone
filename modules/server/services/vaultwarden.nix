# Keystone Vaultwarden Service Module
#
# Vaultwarden is a Bitwarden-compatible password manager server.
# Default subdomain: vaultwarden
# Default port: 8222
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
  cfg = serverCfg.services.vaultwarden;
in
{
  options.keystone.server.services.vaultwarden = serverLib.mkServiceOptions {
    description = "Vaultwarden password manager";
    subdomain = "vaultwarden";
    port = 8222;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.vaultwarden = {
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
