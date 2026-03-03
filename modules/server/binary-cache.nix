# Keystone Binary Cache Module
#
# Serves a Nix binary cache via Harmonia so other machines on the network
# can pull pre-built store paths instead of building from source.
#
# Harmonia binds to localhost only — the consumer is responsible for
# providing nginx/TLS/ACL in front of it.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  serverCfg = config.keystone.server;
  cfg = serverCfg.binaryCache;
in {
  options.keystone.server.binaryCache = {
    domain = mkOption {
      type = types.nullOr types.str;
      default =
        if config.keystone.domain != null
        then "harmonia.${config.keystone.domain}"
        else null;
      defaultText = literalExpression ''"harmonia.''${keystone.domain}"'';
      example = "cache.example.com";
      description = "Domain for the binary cache. Auto-derived from keystone.domain when set.";
    };

    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port for the Harmonia binary cache service.";
    };

    signKeyPaths = mkOption {
      type = types.listOf types.path;
      default = [];
      example = [ "/run/agenix/harmonia-signing-key" ];
      description = ''
        Paths to narinfo signing key files. Store paths are signed with
        these keys so clients can verify cache authenticity.
        Generate with: nix-store --generate-binary-cache-key <name> secret.key public.key
      '';
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "harmonia.example.com-1:AAAA...=";
      description = ''
        Public key corresponding to the signing key.
        When set, the server also configures itself as a cache client,
        and the key is available for the binaryCacheClient module.
      '';
    };
  };

  config = mkIf (serverCfg.enable && cfg.enable) {
    warnings =
      (optional (cfg.signKeyPaths == [])
        "keystone.server.binaryCache.signKeyPaths is empty. Store paths will not be signed and clients will reject them.")
      ++ (optional (cfg.publicKey == null)
        "keystone.server.binaryCache.publicKey is not set. The server won't configure itself as a cache client.");

    services.harmonia = {
      enable = true;
      signKeyPaths = cfg.signKeyPaths;
      settings = {
        bind = "127.0.0.1:${toString cfg.port}";
      };
    };

    # Server also uses its own cache
    nix.settings = mkIf (cfg.domain != null && cfg.publicKey != null) {
      substituters = [ "https://${cfg.domain}" ];
      trusted-public-keys = [ cfg.publicKey ];
    };
  };
}
