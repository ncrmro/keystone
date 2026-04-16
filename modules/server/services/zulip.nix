# Keystone Zulip Service Module
#
# Zulip is an open-source team chat and collaboration platform.
# Default subdomain: zulip
# Default port: 8083
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
  cfg = serverCfg.services.zulip;
in
{
  options.keystone.server.services.zulip = serverLib.mkServiceOptions {
    description = "Zulip team chat";
    subdomain = "zulip";
    port = 8083;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.zulip = {
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
