# Keystone Binary Cache Client Module
#
# Configures a NixOS machine to use a Harmonia binary cache as a substituter.
# Import this on client machines that should pull from the cache.
#
# Usage:
#   keystone.binaryCache = {
#     enable = true;
#     url = "https://harmonia.example.com";
#     publicKey = "harmonia.example.com-1:AAAA...=";
#   };
#
{
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.keystone.binaryCache;
in {
  options.keystone.binaryCache = {
    enable = mkEnableOption "Keystone binary cache client";

    url = mkOption {
      type = types.str;
      example = "https://harmonia.example.com";
      description = "URL of the Harmonia binary cache.";
    };

    publicKey = mkOption {
      type = types.str;
      example = "harmonia.example.com-1:AAAA...=";
      description = "Public key for verifying store path signatures from the cache.";
    };
  };

  config = mkIf cfg.enable {
    nix.settings = {
      substituters = [ cfg.url ];
      trusted-public-keys = [ cfg.publicKey ];
    };
  };
}
