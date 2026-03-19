# Keystone Terminal Contacts (Cardamum)
#
# This module provides cardamum (Pimalaya CardDAV CLI) configuration.
# When enabled with a host configured, it generates a cardamum config.toml
# that connects to a CardDAV endpoint.
#
# Credentials default from the mail module — if mail is already configured,
# only `contacts.enable = true` is needed for Stalwart.
#
# ## Stalwart (self-hosted) Example
#
# ```nix
# keystone.terminal.contacts = {
#   enable = true;
#   # All other options auto-default from keystone.terminal.mail
# };
# ```
#
# ## iCloud Example
#
# Uses the same App-Specific Password as iCloud mail.
#
# ```nix
# keystone.terminal.contacts = {
#   enable = true;
#   accountName = "icloud";
#   url = "https://contacts.icloud.com";
#   login = "user@icloud.com";
#   passwordCommand = "rbw get icloud-app-password";
# };
# ```
#
# ## Gmail Note
#
# Google deprecated CardDAV for new apps. Use the Google People API or
# export contacts as vCard from contacts.google.com instead.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.contacts;
  mailCfg = config.keystone.terminal.mail;
in
{
  options.keystone.terminal.contacts = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable contacts CLI tools (cardamum)";
    };

    accountName = mkOption {
      type = types.str;
      default = mailCfg.accountName;
      description = "Account name in Cardamum config";
    };

    host = mkOption {
      type = types.str;
      default = mailCfg.host;
      description = "CardDAV server hostname (defaults to mail host)";
    };

    login = mkOption {
      type = types.str;
      default = mailCfg.login;
      description = "CardDAV username (defaults to mail login)";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = mailCfg.passwordCommand;
      description = "Command to retrieve the password (defaults to mail passwordCommand)";
    };

    url = mkOption {
      type = types.str;
      default = "";
      description = ''
        CardDAV home URI. When empty, defaults to https://{host}/dav/card (Stalwart).
        Set explicitly for external providers:
          iCloud: https://contacts.icloud.com
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.cardamum
    ];

    # Generate cardamum config only when host or url is configured
    xdg.configFile."cardamum/config.toml" = mkIf (cfg.host != "" || cfg.url != "") {
      text =
        let
          # Use explicit url if set; otherwise build Stalwart's default path.
          # Stalwart's /.well-known/carddav redirects to /dav/card, but cardamum's
          # discovery PROPFIND to the root URL gets a 400 from nginx — use direct
          # path instead of discovery (same issue as CalDAV, see calendar.nix).
          cardDavUri = if cfg.url != "" then cfg.url else "https://${cfg.host}/dav/card";
        in
        ''
          [accounts.${cfg.accountName}]
          default = true

          carddav.home-uri = "${cardDavUri}"
          carddav.auth.basic.username = "${cfg.login}"
          carddav.auth.basic.password.command = ["sh", "-c", "${cfg.passwordCommand}"]
        '';
    };
  };
}
