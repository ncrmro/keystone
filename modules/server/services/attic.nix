# Keystone Attic Service Module
#
# Attic is a Nix binary cache server.
# Default subdomain: cache
# Default port: 8199
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
  cfg = serverCfg.services.attic;
in
{
  options.keystone.server.services.attic =
    serverLib.mkServiceOptions {
      description = "Attic Nix binary cache server";
      subdomain = "cache";
      port = 8199;
      access = "tailscale";
      maxBodySize = "4G";
    }
    // {
      environmentFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to environment file with ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64";
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public key for nix substituter verification (optional)";
      };
    };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.attic = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };

    services.atticd = {
      enable = true;
      environmentFile = cfg.environmentFile;
      settings = {
        listen = "127.0.0.1:${toString cfg.port}";
        storage = {
          type = "local";
          path = "/var/lib/atticd";
        };
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "6 months";
        };
      };
    };

    # Self-configure as client if publicKey and domain are set
    keystone.binaryCache = lib.mkIf (cfg.publicKey != null && config.keystone.domain != null) {
      enable = true;
      url = "https://${cfg.subdomain}.${config.keystone.domain}";
      publicKey = cfg.publicKey;
    };
  };
}
