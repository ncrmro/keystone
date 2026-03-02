# Keystone Terminal Secrets (rbw - Bitwarden/Vaultwarden CLI)
#
# This module provides rbw (unofficial Bitwarden CLI) configuration.
# rbw is a Rust-based alternative with better ergonomics and session caching.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.secrets = {
#   enable = true;
#   email = "me@example.com";
#   baseUrl = "https://vaultwarden.example.com";
# };
# ```
#
# ## Usage
#
# ```bash
# rbw unlock              # Unlock vault (prompts for master password)
# rbw get "GitHub Token"  # Get a secret
# rbw list                # List all entries
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.secrets;
in
{
  options.keystone.terminal.secrets = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable rbw (Bitwarden/Vaultwarden CLI)";
    };

    email = mkOption {
      type = types.str;
      default = "";
      description = "Email address for Bitwarden/Vaultwarden account";
    };

    baseUrl = mkOption {
      type = types.str;
      default = "";
      description = "Vaultwarden server URL (leave empty for official Bitwarden)";
      example = "https://vaultwarden.example.com";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    programs.rbw = {
      enable = true;
      settings = {
        email = cfg.email;
        base_url = mkIf (cfg.baseUrl != "") cfg.baseUrl;
        pinentry = pkgs.pinentry-gnome3;
      };
    };
  };
}
