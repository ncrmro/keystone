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
  pkgs,
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
        default = "/run/agenix/attic-server-token-key";
        description = "Path to env file with ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64. Defaults to conventional agenix secret.";
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public key for nix substituter verification (optional)";
      };
    };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    assertions = lib.optional (cfg.environmentFile == "/run/agenix/attic-server-token-key") {
      assertion = config.age.secrets ? "attic-server-token-key";
      message = "keystone.server.services.attic requires age.secrets.\"attic-server-token-key\" to be declared.";
    };

    environment.systemPackages = [ pkgs.attic-client ];

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

    # Self-configure as substituter if publicKey and domain are set
    nix.settings = lib.mkIf (cfg.publicKey != null && config.keystone.domain != null) {
      substituters = [ "https://${cfg.subdomain}.${config.keystone.domain}" ];
      trusted-public-keys = [ cfg.publicKey ];
    };
  };
}
